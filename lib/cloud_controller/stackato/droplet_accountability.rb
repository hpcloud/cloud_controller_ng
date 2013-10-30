
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
      StackatoRedisClient.redis &block
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
          update_stats_for_all_droplets
          sleep STATS_UPDATER_SLEEP
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
          housekeeping
          sleep HOUSEKEEPING_SLEEP
        end
      end
    end

    def self.get_app_stats(app)

      logger.debug2("Getting droplet stats for app #{app.guid}")

      droplet_id = app.guid

      indices = {}
      return indices if (app.nil? || !app.started?)

      instance_ids = redis { |r| r.smembers("droplet:#{droplet_id}:instances") }

      instance_ids.each do |instance_id|
        logger.debug2("Getting droplet #{droplet_id} stats for instance #{instance_id}")

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
      deas = redis { |r| r.smembers "deas" }
      deas.each do |dea|
        dea_exists = redis { |r| r.exists("dea:#{dea}") } == 1
        unless dea_exists
          redis { |r| r.srem("deas", dea) }
        end
      end

      droplet_ids = redis { |r| r.smembers("droplets") }
      droplet_ids.each do |droplet_id|
        instance_ids = redis { |r| r.smembers("droplet:#{droplet_id}:instances") }
        if ((instance_ids.is_a? Array) && (instance_ids.count > 0))
          instance_ids.each do |instance_id|
            droplet_exists = redis { |r| r.exists("droplet:#{droplet_id}:instance:#{instance_id}") } == 1
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
      droplets = redis { |r| r.smembers("droplets") }
      droplets.each do |droplet_id|
        update_stats(droplet_id)
      end
    end

    def self.update_stats(droplet_id)

      request = {
        :droplet => droplet_id.to_i,
        :include_stats => true
      }

      logger.debug2 "Updating stats for app #{droplet_id}"
      instance_ids = redis { |r| r.smembers("droplet:#{droplet_id}:instances") }

      logger.debug2 "Testing #{instance_ids.count} instances"

      instance_ids.each do |instance_id|
        instance_request = {
          :instances => [instance_id]
        }
        instance_request.merge(request)
        sid = message_bus.request("dea.find.droplet", Yajl::Encoder.encode(instance_request) ) do |instance_json, error|
          instance = Yajl::Parser.parse(instance_json).with_indifferent_access
          logger.debug2 "About to process an instance"
          process_instance(instance)
        end

        # timeout this request in 30 secs
        message_bus.timeout(sid, 30) {}

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
      droplets = msg["droplets"]

      # make sure we know about this DEA already
      dea_exists = redis { |r| r.exists("dea:#{dea}") } == 1

      unless dea_exists
        # DEAs announce yourselves!
        message_bus.request("dea.status", "{}") do |response, error|
          logger.debug2("Got a reply to dea.status : #{response}")
          handle_dea_status(response)
        end
      end

      logger.debug2("Processing #{droplets.size} droplets...")
      droplets.each do |drop|
        logger.debug2("Processing droplet : #{drop}")
        droplet_id = drop["droplet"]
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

    def self.process_instance(instance)

      logger.debug2 "Processing individual instance #{instance.inspect}"

      droplet_id = instance["droplet"]
      instance_id = instance["instance"]
      stats = instance["stats"]

      return unless stats

      uptime = stats.delete("uptime")
      usage = stats.delete("usage")

      return unless usage

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
