require "cloud_controller/backends"
module VCAP::CloudController
  class StackatoBackends < Backends
    def initialize(config, message_bus, dea_pool, stager_pool, health_manager_client)
      super(config, message_bus, dea_pool, stager_pool)
      @health_manager_client = health_manager_client
    end

    def update_autoscaling_fields(changes)
      @health_manager_client.update_autoscaling_fields(changes)
    end

    def react_to_droplet_hash_change(app)
      if app.started?
        stage_if_needed(app) do |staging_result|
          Dea::Client.start(app, :instances_to_start => app.instances) # this will temporarily cause 2x instances, allowing the HM to gracefully terminate the old ones
          @health_manager_client.notify_of_new_live_version( :app_id => app.guid, :version => app.version )
          broadcast_app_updated(app)
        end
      else
        Dea::Client.stop(app)
        broadcast_app_updated(app)
      end
    end
    
    def react_to_version_change(app)
      @health_manager_client.notify_of_new_live_version( :app_id => app.guid, :version => app.version )
      if app.started?
        stage_if_needed(app) do |staging_result|
          Dea::Client.start(app, :instances_to_start => app.instances) # this will temporarily cause 2x instances, allowing the HM to gracefully terminate the old ones
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

    private

    def stage_app(app, &completion_callback)
      validate_app_for_staging(app)
      blobstore_url_generator = CloudController::DependencyLocator.instance.blobstore_url_generator
      task = VCAP::CloudController::Dea::StackatoAppStagerTask.new(@config, @message_bus, app, @dea_pool, @stager_pool, blobstore_url_generator)
      task.stage(&completion_callback)
    end

    def stage_if_needed(app, &success_callback)
      if app.needs_staging?
        # Bug 104558 - Allow for dead droplet-slots to be made available
        num_tries = @config[:staging].fetch(:num_repeated_tries, 10)
        delay = @config[:staging].fetch(:time_between_tries, 3)
        (num_tries + 1).times do | iter |
          begin
            app.last_stager_response = stage_app(app, &success_callback)
            if iter > 0
              logger.info("Staged #{app.name}")
            end
            break
          rescue Errors::ApiError => e
            raise if iter == num_tries || e.name != "StagingError"
            logger.warn("#{iter + 1}/#{num_tries}: Waiting #{delay} secs for more resources to stage #{app.name}")
            sleep delay
          end
        end
      else
        success_callback.call(:started_instances => 0)
      end
    end

  end
end
    
