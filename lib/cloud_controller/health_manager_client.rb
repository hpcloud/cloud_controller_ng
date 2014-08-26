module VCAP::CloudController
  class HealthManagerClient
    APP_STATE_BULK_MAX_APPS = 50

    def initialize(message_bus, config)
      @message_bus = message_bus
      @config = config # only in here for hm9000 compatibility
    end

    def healthy_instances(apps)
      batch_request = apps.kind_of?(Array)
      apps = Array(apps)

      message = {
        :droplets => apps.map do |app|
          { :droplet => app.guid, :version => app.version }
        end
      }

      request_options = {
        :result_count => apps.size,
        :timeout => 1,
      }

      resp = hm_request("health", message, request_options)

      if batch_request
        resp.inject({}) do |result, r|
          result[r["droplet"]] = r["healthy"]
          result
        end
      elsif resp && !resp.empty?
        resp.first["healthy"]
      else
        0
      end
    end
    
    def healthy_instances_bulk(apps)
      healthy_instances(apps)
    end

    def find_crashes(app)
      message = { :droplet => app.guid, :state => :CRASHED }
      request_options = { :timeout => 2 }
      crashed_instances = hm_request("status", message, request_options).first
      crashed_instances ? crashed_instances["instances"] : []
    end

    def find_flapping_indices(app)
      message = { :droplet => app.guid, :version => app.version, :state => :FLAPPING }
      request_options = { :result_count => app.instances, :timeout => 2}
      response = hm_request("status", message, request_options).first
      (response && response["indices"]) ? response["indices"] : []
    end

    def update_autoscaling_fields(args)
      message_bus.publish("health_manager.autoscaling_settings", args)
    end

    def notify_of_new_live_version(args)
      message_bus.publish("healthmanager.dropletversion", args)
    end

    private

    attr_reader :config, :message_bus

    def hm_request(cmd, args = {}, opts = {})
      subject = "healthmanager.#{cmd}"
      msg = "sending subject: '#{subject}' with args: '#{args}'"
      msg << " and opts: '#{opts}'"
      logger.debug msg
      message_bus.synchronous_request(subject, args, opts)
    end

    def logger
      @logger ||= Steno.logger("cc.healthmanager.client")
    end
  end
end
