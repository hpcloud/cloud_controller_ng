require "steno"

require File.expand_path("../dea/dea_client", __FILE__)

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
        logger.debug("QQQ process_start(payload:#{payload})")
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
      return unless app
      return unless app.started?
      return unless version == app.version
      # If staging has not failed, but bits were not uploaded
      # ignore start command from HM
      return if !app.droplet_hash && !app.staging_failed?

      current_running = running[app.version] || 0
      return unless current_running < app.instances

      dea_client.start_instances(app, indices)
    end

    def process_stop(payload)
      begin
        logger.debug("QQQ process_stop(payload:#{payload})")
        app_id = payload.fetch("droplet")
        instances = payload.fetch("instances")
        running = payload.fetch("running")
      rescue KeyError => e
        Loggregator.emit_error(app_id, "Bad request from health manager: #{e.message}, payload: #{payload}")
        logger.error "cloudcontroller.hm.malformed-request",
          :error => e.message,
          :payload => payload
        return
      end

      app = App[:guid => app_id]

      if !app
        stop_runaway_app(app_id)
      elsif stop_instances?(app, instances, running)
        dea_client.stop_instances(app_id, instances.keys)
      end
    end

    def adjust_instances(decoded_msg)
      logger.debug("QQQ: >> health_manager.adjust_instances: #{decoded_msg}")
      begin
        decoded_msg = decoded_msg.symbolize_keys
        logger.debug("QQQ: Fixed decoded_msg: #{decoded_msg}")
        factory = CloudController::ControllerFactory.new({}, logger, {}, decoded_msg, {})
        controller = factory.create_controller(VCAP::CloudController::AppsController)
        app_guid = decoded_msg.delete(:guid)
        controller.adjust_instances(app_guid, decoded_msg)
        logger.debug("+ apps_controller.update(app_guid:#{app_guid}, decoded_msg:#{decoded_msg})")
      rescue => e
        logger.debug("QQQ: *** : error updating by hand: health_manager.adjust_instances: Error: #{e.message}\n#{e.backtrace.join("\n")}\n")
      end
      logger.debug("QQQ: << health_manager.adjust_instances")
    end
      
    def process_request_autoscaling_settings(decoded_msg)
      logger.debug("QQQ: >> process_request_autoscaling_settings: #{decoded_msg}")
      decoded_msg = decoded_msg.symbolize_keys
      app = App[:guid => decoded_msg[:guid]]
      if !app
        logger.debug("QQQ: process_request_autoscaling_settings: no guid in #{decoded_msg}")
        return
      end
      return if !app
      dea_client.update_autoscaling_fields(app)
      logger.debug("QQQ: << process_request_autoscaling_settings: #{decoded_msg}")
    end

    def stop_app(app)
      dea_client.stop(app)
    end

    def stop_runaway_app(app_id)
      dea_client.stop(App.new(:guid => app_id))
    end

    def stop_instances?(app, instances, running)
      instances.group_by { |_, v| v }.each do |version, versions|
        instances_remaining =
          if running.key?(version)
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
  end
end
