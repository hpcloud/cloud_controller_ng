require "steno"

require File.expand_path("../dea/client", __FILE__)

module VCAP::CloudController
  class << self
    attr_accessor :health_manager_respondent
  end

  class HealthManagerRespondent
    attr_reader :logger, :config
    attr_reader :message_bus, :dea_client

    # Semantically there should only be one such thing, although
    # I'm hesitant about making singletons
    # - Jesse
    def initialize(dea_client, message_bus)
      @logger = Steno.logger("cc.hm")
      @dea_client = dea_client
      @message_bus = message_bus
    end

    def handle_requests
      message_bus.subscribe("health.stop", :queue => "cc") do |decoded_msg|
        process_stop(decoded_msg)
      end

      message_bus.subscribe("health.start", :queue => "cc") do |decoded_msg|
        process_start(decoded_msg)
      end

      message_bus.subscribe("health_manager.adjust_instances", :queue => "cc") do |decoded_msg|
        adjust_instances(decoded_msg)
      end
      
      message_bus.subscribe("health_manager.request_autoscaling_settings", :queue => "cc") do |decoded_msg|
        process_request_autoscaling_settings(decoded_msg)
      end
    end
    
    def process_start(payload)
      begin
        app_id = payload.fetch("droplet")
        indices = payload.fetch("indices")
        version = payload.fetch("version")
        running = payload.fetch("running")
      rescue KeyError => e
        Loggregator.emit_error(app_id, "Bad request from health manager: #{e.message}, payload: #{payload}")
        logger.error "cloudcontroller.hm.malformed-request",
          :error => e.message,
          :payload => payload
        return
      end

      app = App[:guid => app_id]
      should_start, reason = instance_needs_to_start?(app, version, indices, running)
      if should_start
        dea_client.start_instance_at_index(app, indices[0])
        logger.info "cloudcontroller.health_manager.will-start", :reason => reason, :payload => message
      else
        logger.info "cloudcontroller.health_manager.will-not-start", :payload => message
      end

      dea_client.start_instances(app, indices)
    end

    def process_stop(payload)
      begin
        app_guid = payload.fetch("droplet")
        instances = payload.fetch("instances")
        running = payload.fetch("running")
      rescue KeyError => e
        Loggregator.emit_error(app_guid, "Bad request from health manager: #{e.message}, payload: #{payload}")
        logger.error "cloudcontroller.hm.malformed-request",
          :error => e.message,
          :payload => payload
        return
      end
      # Pre Stackato v3.4 merge code:
      app = App[:guid => app_guid]
      if !app
        stop_runaway_app(app_guid)
      elsif stop_instances?(app, instances, running)
        dea_client.stop_instances(app_guid, instances.keys)
      end
    end

    def stop_runaway_app(app_id)
      dea_client.stop(App.new(:guid => app_id))
    end

    def stop_instances?(app, instances, running)
      instances.group_by { |_, v| v }.each do |version, versions|
        logger.debug(" version: #{version}, versions:#{versions}")
        instances_remaining =
          if running.key?(version)
            logger.debug("running[version]: #{running[version]}")
            running[version] - versions.size
          else
            0
          end

        if version != app.version
          unless (running[app.version] || 0) > 0
            return false
          end
        elsif instances_remaining < app.instances && app.started?
          Loggregator.emit_error(app.guid, "Bad request from health manager")
          logger.error "cloudcontroller.hm.invalid-request",
                       :instances => instances, :app => app.guid,
                       :desired_instances => app.instances,
                       :remaining_instances => instances_remaining

          return false
        end
      end
      true
    end

    def instance_needs_to_stop?(app_guid, version, instances, running)
      app = App[:guid => app_guid]

      if !app
        return true, "App not found"
      end
      
      if app.staging_failed?
        return true, "App failed to stage"
      end
      
      if app.version != version
        return true, "Version is not current (#{app.version})"
      end

      if app.stopped?
        return true, "App is in STOPPED state"
      end

      false
    end

    def instance_needs_to_start?(app, version, indices, running)
      if !app
        return false, "App not found"
      end

      if app.version != version
        return false, "Version is not current (#{app.version})"
      end

      if indices.size != 1
        return false, "Got #{indices.size} indices (#{indices}), expecting 1"
      end
      instance_index = indices[0]
      if instance_index >= app.instances
        return false, "Instance index is outside desired number of instances (#{app.instances})"
      end

      if !app.droplet_hash
        return false, "App is not uploaded (no droplet hash)"
      end

      if !app.staged?
        return false, "App is not staged"
      end

      if !app.started?
        return false, "App is not in STARTED state"
      end
      
      current_running = running[app.version] || 0
      if current_running >= app.instances
        return false, "running[version:#{app.version}] = #{current_running}, but app.instances is #{app.instances}"
      end
      true
    end

    def adjust_instances(decoded_msg)
      decoded_msg = decoded_msg.symbolize_keys
      factory = CloudController::ControllerFactory.new({}, logger, {}, decoded_msg, {})
      controller = factory.create_controller(VCAP::CloudController::AppsController)
      app_guid = decoded_msg.delete(:guid)
      controller.adjust_instances(app_guid, decoded_msg, true) # force no version creation
    end
      
    def process_request_autoscaling_settings(decoded_msg)
      decoded_msg = decoded_msg.symbolize_keys
      app = App[:guid => decoded_msg[:guid]]
      return if !app
      dea_client.update_autoscaling_fields(app)
    end
    
  end
end
