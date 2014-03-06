
require 'yajl'
require "cloud_controller/stackato/redis_client"

module VCAP::CloudController
  class StackatoDropletAccountability

    STATS_UPDATES_EXPIRY = 30 # secs
    STATS_UPDATER_SLEEP = 30 # secs
    HOUSEKEEPING_SLEEP = 2 # secs

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
      start_housekeeping
      subscribe_to_dea_heartbeats
    end

    def self.start_stats_updater
      @@stats_updater_thread ||= nil
      if @@stats_updater_thread
        raise Errors::StackatoDropletAccountabilityStatsUpdaterAlreadyRunning.new
      end
      logger.info("Droplet accountability stats updater starting")
      @@stats_updater_thread = Thread.new do
        while true
          sleep STATS_UPDATER_SLEEP
          update_stats_for_all_droplets
        end
      end
    end

    def self.start_housekeeping
      @@housekeeping_thread ||= nil
      if @@housekeeping_thread
        raise Errors::StackatoDropletAccountabilityHouseKeepingAlreadyRunning.new
      end
      logger.info("Droplet accountability housekeeping starting")
      @@housekeeping_thread = Thread.new do
        while true
          sleep HOUSEKEEPING_SLEEP
          housekeeping
        end
      end
    end

    def self.get_all_dea_stats
      all_dea_stats = []
      DeaClient.active_deas.each do | dea |
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
      mb = 1024 * 1024
      dea_stats = {:total_allocated => 0, :total_used => 0}
      keys = redis { |r| r.keys("dea:#{dea_id}:instances:*") } #TODO may want to look at maintaining a set
      if !keys.nil? && keys.length > 0
        instances_on_dea = redis { |r| r.mget(keys || []) }
        instances_on_dea.each do |instance|
          if !instance.nil?
            instance_data = instance.split(':') 
            dea_stats[:total_used] += instance_data[0].to_i / mb
            dea_stats[:total_allocated] += instance_data[1].to_i / mb
          end
        end
      end
      dea_stats
    end

    def self.get_app_stats(app)

      logger.debug2("Getting droplet stats for app.guid:#{app.guid}")

      droplet_id = app.guid

      indices = {}
      return indices if (app.nil? || !app.started?)

      instance_ids = redis { |r| r.smembers("droplet:#{droplet_id}:instances") }

      instance_ids.each do |instance_id|
        logger.debug2("Getting droplet instance stats for droplet_id:#{droplet_id} instance_id:#{instance_id}")

        keyname = "droplet:#{droplet_id}:instance:#{instance_id}"
        index = redis { |r| r.hget(keyname, "index") }

        next unless index

        index = index.to_i

        if index >= 0 && index < app.instances
          stats_ar = redis { |r| r.hmget(keyname, "uptime", "disk", "mem", "cpu", "stats") }

          next unless stats_ar[4]

          stats = Yajl::Parser.parse(stats_ar[4])

          stats.merge!(
            "uptime" => stats_ar[0],
            "usage"  => {
              "disk" => stats_ar[1],
              "mem"  => stats_ar[2],
              "cpu"  => stats_ar[3],
              "time" => Time.now.to_s,
            }
          )

          indices[index] = {
            "state" => redis { |r| r.hget(keyname, "state") },
            "stats" => stats,
          }
        end
      end

      app.instances.times do |index|
        index_entry = indices[index]
        unless index_entry
          indices[index] = {
            "state" => "DOWN",
            "since" => Time.now.to_i
          }
        end
      end

      indices
    end

    def self.housekeeping
      logger.debug2 "Housekeeping iteration..."
      deas = redis { |r| r.smembers "deas" }
      deas.each do |dea|
        logger.debug2 "Housekeeping for dea:#{dea}"
        dea_exists = redis { |r| r.exists("dea:#{dea}") }
        unless dea_exists
          redis { |r| r.srem("deas", dea) }
        end
      end

      droplet_ids = redis { |r| r.smembers("droplets") }
      droplet_ids.each do |droplet_id|
        instance_ids = redis { |r| r.smembers("droplet:#{droplet_id}:instances") }
        logger.debug2 "Housekeeping for droplet droplet_id:#{droplet_id} instance_ids:#{instance_ids}"
        if ((instance_ids.is_a? Array) && (instance_ids.count > 0))
          instance_ids.each do |instance_id|
            droplet_exists = redis { |r| r.exists("droplet:#{droplet_id}:instance:#{instance_id}") }
            unless droplet_exists
              redis { |r| r.srem("droplet:#{droplet_id}:instances", instance_id) }
            end
          end
        else
          redis { |r| r.del("droplet:#{droplet_id}:instances") }
          redis { |r| r.srem("droplets", droplet_id) }
        end
      end
    end

    def self.update_stats_for_all_droplets
      logger.debug2 "Stats update iteration..."
      droplets = redis { |r| r.smembers("droplets") }
      droplets.each do |droplet_id|
        update_stats_for_droplet(droplet_id)
      end
    end

    def self.update_stats_for_droplet(droplet_id)
      instance_ids = redis { |r| r.smembers("droplet:#{droplet_id}:instances") }
      logger.debug2 "Stats update for droplet droplet_id:#{droplet_id} instances=#{instance_ids}"
      instance_ids.each do |instance_id|
        request = {
          :droplet => droplet_id,
          :instances => [instance_id],
          :include_stats => true
        }
        logger.debug2 "Request dea.find.droplet for droplet_id:#{droplet_id} instance_id:#{instance_id} request:#{request}"
        # timeout this request in 30 secs
        message_bus.request("dea.find.droplet", request, {:timeout => 30, :result_count => 1}) do |response|
          update_stats_for_droplet_instance(response)
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
      logger.debug2("DEA heartbeat received")

      dea = msg["dea"]
      droplets = msg["droplets"]

      # make sure we know about this DEA already
      dea_exists = redis { |r| r.exists("dea:#{dea}") }

      unless dea_exists
        # DEAs announce yourselves!
        logger.debug2("DEA heartbeat. dea.status")
        # timeout this request in 30 secs
        message_bus.request("dea.status", nil, :timeout => 30) do |response|
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

        redis { |r| r.sadd("droplets", droplet_id) }
        redis { |r| r.sadd("droplet:#{droplet_id}:instances", instance_id) }
        redis { |r| r.hmset("droplet:#{droplet_id}:instance:#{instance_id}",
          "state",   drop["state"],
          "index",   drop["index"],
          "dea",     dea,
          "version", drop["version"])
        }
        redis { |r| r.expire("droplet:#{droplet_id}:instance:#{instance_id}",
          STATS_UPDATES_EXPIRY)
        }
      end
    end

    def self.handle_dea_status(msg)
      redis { |r| r.sadd("deas", msg["id"]) }
      redis { |r| r.hmset(
          "dea:#{msg["id"]}",
          "ip", msg["ip"],
          "version", msg["version"]
        )
      }
      redis { |r| r.expire("dea:#{msg["id"]}", STATS_UPDATES_EXPIRY) }
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
      mem = usage["mem"]
      mem_quota = stats["mem_quota"]

      return unless usage

      # Save the instances stats against the dea for dea driven memory reporting
      dea_instance_key  = "dea:#{dea_id}:instances:#{instance_id}"
      redis { |r| r.set(dea_instance_key, "#{mem}:#{mem_quota}" )}
      redis { |r| r.expire(
          dea_instance_key,
          STATS_UPDATES_EXPIRY
        )
      }

      # Save the instance stats against the droplet for app driven reporting
      redis { |r| r.hmset(
          "droplet:#{droplet_id}:instance:#{instance_id}",
          "stats",  Yajl::Encoder.encode(stats),
          "uptime", uptime,
          "mem",    usage["mem"],
          "disk",   usage["disk"],
          "cpu",    usage["cpu"],
        )
      }
      redis { |r| r.expire(
          "droplet:#{droplet_id}:instance:#{instance_id}",
          STATS_UPDATES_EXPIRY
        )
      }
    end

  end
end
