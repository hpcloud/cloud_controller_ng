require "cloud_controller/backends/stagers"

module VCAP::CloudController
  class StackatoStagers < Stagers
    
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

    def dea_stager(app)
      Dea::StackatoStager.new(app, @config, @message_bus, @dea_pool, @stager_pool, @runners)
    end
    
    private

    def logger
      @logger ||= Steno.logger('cc.stackato.backends.stagers')
    end
    
    def stage_app(app, &completion_callback)
      validate_app(app)
      blobstore_url_generator = CloudController::DependencyLocator.instance.blobstore_url_generator
      docker_registry = CloudController::DependencyLocator.instance.docker_registry
      task = VCAP::CloudController::Dea::StackatoAppStagerTask.new(@config, @message_bus, app, @dea_pool, @stager_pool, blobstore_url_generator, docker_registry)
      task.stage(&completion_callback)
    end
    
  end
end
