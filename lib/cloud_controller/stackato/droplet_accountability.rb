
require 'yajl'
require "cloud_controller/stackato/redis_client"

module VCAP::CloudController
  class StackatoDropletAccountability

    STATS_UPDATES_EXPIRY = 5 * 60 # secs
    STATS_UPDATER_SLEEP = 30 # secs
    STATS_UPDATER_TIMEOUT = 30 # secs

    def self.configure(config, message_bus)
      @@cc_config = config
      @@message_bus = message_bus
    end

    def self.logger
      @@logger ||= Steno.logger("cc.stackato.droplet_accountability")
    end

    def self.redis &block
      EphemeralRedisClient.redis &block
    end

    def self.message_bus
      @@message_bus ||= nil
      unless @@message_bus
        raise StackatoDropletAccountabilityMessageBusNotConfigured.new
      end
      @@message_bus
    end

    def self.start
      start_stats_updater
      subscribe_to_dea_heartbeats
    end

    def self.start_stats_updater
      @@stats_updater_thread ||= nil
      if @@stats_updater_thread
        raise Errors::ApiError.new_from_details("StackatoDropletAccountabilityStatsUpdaterAlreadyRunning")
      end
      logger.info("Droplet accountability stats updater starting")
      @@stats_updater_thread = Thread.new do
        while true
          sleep STATS_UPDATER_SLEEP
          update_stats_for_all_droplets
        end
      end
    end

    def self.get_all_dea_stats
      all_dea_stats = []
      Dea::Client.active_deas.each do | dea |
        stats = self.get_dea_stats(dea.dea_id)
        stats[:dea_id] = dea.dea_id
        stats[:dea_ip] = dea.dea_ip
        stats[:total_available] = dea.available_memory
        stats[:total_physical] = dea.physical_memory
        all_dea_stats << stats
      end
      all_dea_stats
    end

    def self.get_dea_stats(dea_id)
      total_allocated, total_used = 0, 0
      begin
        keys = redis { |r| r.keys("dea:#{dea_id}:instances:*") }
      rescue Redis::BaseConnectionError
        logger.debug2 "Ignoring connection error getting instances"
      rescue Redis::CommandError => e
        logger.error "Error getting dea instances: #{e}"
      end
      if !keys.nil? && keys.length > 0
        instances_on_dea = redis { |r| r.mget(keys || []) }
        instances_on_dea.compact.each do |instance|
          instance_data = instance.split(':')
          total_used += instance_data[0].to_f / 1024.0 / 1024.0
          total_allocated += instance_data[1].to_f / 1024.0 / 1024.0
        end
      end
      return { total_allocated: total_allocated.to_i, total_used: total_used.to_i }
    end

    def self.get_app_stats(app)

      logger.debug2("Getting droplet stats for app.guid:#{app.guid}")

      droplet_id = app.guid

      indices = {}
      return indices if (app.nil? || !app.started?)

      begin
        instance_keys = redis { |r| r.keys("droplet:#{droplet_id}:instance:*") }
      rescue Redis::BaseConnectionError => e
        logger.warn("Failed to connect to redis to gather statistics for app ID #{app.guid} (#{app.name}: #{e.message})")
        instance_keys = []
      end

      app.instances.times do |index|
        indices[index] = { "state" => "DOWN" }
      end

      instance_keys.each do |keyname|
        instance_id = keyname.split(":").last
        logger.debug2("Getting droplet instance stats for droplet_id:#{droplet_id} instance_id:#{instance_id}")

        begin
          (index, uptime, disk, mem, cpu, stats, state) = redis do |r|
            r.hmget(keyname, "index", "uptime", "disk", "mem", "cpu", "stats", "state")
          end
        rescue Redis::BaseConnectionError => e
          logger.warn "Connection error getting droplet stats for #{droplet_id}:#{instance_id}: #{e}"
        end

        next unless index
        index = index.to_i
        next unless index >= 0 && index < app.instances
        next unless stats

        stats = Yajl::Parser.parse(stats)

        stats.merge!(
          "uptime" => uptime,
          "usage"  => {
            "disk" => disk,
            "mem"  => mem,
            "cpu"  => cpu,
          }
        )

        indices[index] = {
          "state" => state,
          "stats" => stats,
        }
      end

      indices
    end

    def self.update_stats_for_all_droplets
      logger.debug2 "Stats update iteration..."
      begin
        instances = redis { |r| r.keys("droplet:*:instance:*") }
      rescue Redis::BaseConnectionError
        logger.debug "Connection error getting instances for droplets"
        instances = []
      end
      droplets = Hash.new { |h, k| h[k] = [] }
      instances.each do |instance_key|
        _, droplet_id, _, instance_id = instance_key.split(":")
        droplets[droplet_id] << instance_id
      end
      droplets.each_pair do |droplet_id, instance_ids|
        update_stats_for_droplet(droplet_id, instance_ids)
      end
    end

    def self.update_stats_for_droplet(droplet_id, instance_ids)
      logger.debug2 "Stats update for droplet droplet_id:#{droplet_id} instances=#{instance_ids}"
      instance_ids.each do |instance_id|
        request = {
          :droplet => droplet_id,
          :instances => [instance_id],
          :include_stats => true
        }
        logger.debug2 "Request dea.find.droplet for droplet_id:#{droplet_id} instance_id:#{instance_id} request:#{request}"
        # timeout this request in 30 secs
        message_bus.request("dea.find.droplet", request, {:timeout => STATS_UPDATER_SLEEP, :result_count => 1}) do |response|
          # Ignore timeouts; either the key will expire, or the next attempt will succeed.
          if response[:timeout]
            logger.debug2 "Timed out finding droplet #{droplet_id} instance #{instance_id}"
          else
            update_stats_for_droplet_instance(response)
          end
        end
      end
    end

    def self.subscribe_to_dea_heartbeats
      message_bus.subscribe('dea.heartbeat') do |response, error|
        begin
          handle_dea_heartbeat(response)
        rescue => e
          logger.error("Failed processing dea heartbeat: '#{msg}'")
          logger.error(e)
        end
      end
      message_bus.publish('dea.locate')
    end

    def self.handle_dea_heartbeat(msg)
      dea = msg["dea"]
      logger.debug2("DEA heartbeat received from #{dea}")
      droplets = msg["droplets"]

      # make sure we know about this DEA already
      begin
        dea_exists = redis { |r| r.exists("dea:#{dea}") }
      rescue Redis::BaseConnectionError
        logger.debug "Connection error checking for existing dea info for #{dea}"
        return
      end

      if dea_exists
        begin
          redis { |r| r.expire("dea:#{dea}", STATS_UPDATES_EXPIRY) }
        rescue Redis::BaseConnectionError
          # Do nothing; this will expire by itself later
        end
      else
        # DEAs announce yourselves!
        logger.debug2("DEA heartbeat. dea.status")
        message_bus.request("dea.status", nil, :timeout => STATS_UPDATER_TIMEOUT) do |response|
          logger.debug2("DEA heartbeat. dea.status response:#{response}")
          handle_dea_status(response)
        end
      end

      logger.debug2("DEA heartbeat. Processing #{droplets.size} droplets...")
      droplets.each do |drop|
        droplet_id = drop["droplet"]
        logger.debug2("DEA heartbeat. Processing droplet droplet_id:#{droplet_id} drop:#{drop}")
        instance_id = drop["instance"]

        next unless droplet_id.to_s.match(/^[\da-z\-]+$/)

        instance_key = "droplet:#{droplet_id}:instance:#{instance_id}"

        begin
          redis do |r|
            r.multi do
              r.hmset(instance_key, {
                "state"   => drop["state"],
                "index"   => drop["index"],
                "dea"     => dea,
                "version" => drop["version"]
              }.flatten)
              r.expire(instance_key, STATS_UPDATES_EXPIRY)
            end
          end
        rescue Redis::BaseConnectionError
          logger.debug "DEA heartbeat. Connection error updating instance."
          # Do nothing; either the next update will catch it, or it will expire out
        end
      end
    end

    def self.handle_dea_status(msg)
      return unless msg["id"]
      redis do |r|
        r.multi do
          r.hmset(
            "dea:#{msg["id"]}",
            "ip", msg["ip"],
            "version", msg["version"]
          )
          r.expire("dea:#{msg["id"]}", STATS_UPDATES_EXPIRY)
        end
      end
    rescue Redis::BaseConnectionError
      logger.debug "Connection error updating DEA status"
    end

    def self.update_stats_for_droplet_instance(droplet_instance)

      logger.debug2 "Processing droplet instance #{droplet_instance.inspect}"

      dea_id = droplet_instance["dea"]
      droplet_id = droplet_instance["droplet"]
      instance_id = droplet_instance["instance"]
      stats = droplet_instance["stats"]

      return unless stats

      uptime = stats.delete("uptime")
      usage = stats.delete("usage")
      mem_quota = stats["mem_quota"]

      return unless usage

      mem = usage["mem"]

      # Save the instances stats against the dea for dea driven memory reporting
      dea_instance_key  = "dea:#{dea_id}:instances:#{instance_id}"
      begin
        redis do |r|
          r.multi do
            r.set dea_instance_key, "#{mem}:#{mem_quota}"
            r.expire dea_instance_key, STATS_UPDATES_EXPIRY
          end
        end
      rescue Redis::BaseConnectionError
        logger.debug "Connection error updating DEA droplet stats"
      end

      # Save the instance stats against the droplet for app driven reporting
      droplet_instance_key = "droplet:#{droplet_id}:instance:#{instance_id}"
      begin
        redis do |r|
          r.multi do
            r.hmset(droplet_instance_key,
              "stats",  Yajl::Encoder.encode(stats),
              "uptime", uptime,
              "mem",    usage["mem"],
              "disk",   usage["disk"],
              "cpu",    usage["cpu"],
              "dea",    dea_id
            )
            r.expire droplet_instance_key, STATS_UPDATES_EXPIRY
          end
        end
      rescue Redis::BaseConnectionError
        logger.debug "Connection error updating droplet stats"
      end
    end
  end
end
