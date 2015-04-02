require "cloud_controller/backends/runners"

module VCAP::CloudController
  class StackatoRunners < Runners
    attr_writer :stagers
    def initialize(config, message_bus, dea_pool, stager_pool, health_manager_client)
      super(config, message_bus, dea_pool, stager_pool)
      @health_manager_client = health_manager_client
    end
    
    def update_autoscaling_fields(changes)
      @health_manager_client.update_autoscaling_fields(changes)
    end
    
    def react_to_version_change(app)
      @health_manager_client.notify_of_new_live_version( :app_id => app.guid, :version => app.version )
      if app.started?
        @stagers.stage_if_needed(app) do |staging_result|
          Dea::Client.start(app, :instances_to_start => app.instances) # this will temporarily cause 2x instances, allowing the HM to gracefully terminate the old ones
          broadcast_app_updated(app)
        end
      else
        Dea::Client.stop(app)
        broadcast_app_updated(app)
      end
    end

    def react_to_droplet_hash_change(app)
      if app.started?
        @stagers.stage_if_needed(app) do |staging_result|
          Dea::Client.start(app, :instances_to_start => app.instances) # this will temporarily cause 2x instances, allowing the HM to gracefully terminate the old ones
          @health_manager_client.notify_of_new_live_version( :app_id => app.guid, :version => app.version )
          broadcast_app_updated(app)
        end
      else
        Dea::Client.stop(app)
        broadcast_app_updated(app)
      end
    end

    def broadcast_app_updated(app)
      @message_bus.publish("droplet.updated", droplet: app.guid)
    end

  end
end
