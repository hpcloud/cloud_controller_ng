require 'cloud_controller/stackato/dea/app_stager_task'

module VCAP::CloudController
  module Dea
    class Runner
      EXPORT_ATTRIBUTES = [
        :instances,
        :state,
        :memory,
        :package_state,
        :version
      ]

      def initialize(app, config, message_bus, dea_pool, stager_pool)
        @logger ||= Steno.logger('cc.dea.backend')
        @app = app
        @config = config
        @message_bus = message_bus
        @dea_pool = dea_pool
        @stager_pool = stager_pool
      end

      def requires_restage?
        false
      end

      def stage
        blobstore_url_generator = CloudController::DependencyLocator.instance.blobstore_url_generator
        docker_registry = CloudController::DependencyLocator.instance.docker_registry
        task = StackatoAppStagerTask.new(@config, @message_bus, @app, @dea_pool, @stager_pool, blobstore_url_generator, docker_registry)
        @app.last_stager_response = task.stage { |staging_result| start(staging_result) }
      end

      def scale
        changes = @app.previous_changes
        delta = changes[:instances][1] - changes[:instances][0]

        Client.change_running_instances(@app, delta)
      end

      def start(staging_result={})
        started_instances = staging_result[:started_instances] || 0
        Client.start(@app, instances_to_start: @app.instances - started_instances)
      end

      def stop
        app_stopper = AppStopper.new(@message_bus)
        app_stopper.publish_stop(droplet: @app.guid)
      end

      def update_routes
      end

      def desire_app_message
        raise NotImplementedError
      end

      def desired_app_info
        hash = {}
        EXPORT_ATTRIBUTES.each do |field|
          hash[field.to_s] = @app.values.fetch(field)
        end
        hash['id'] = @app.guid
        hash['updated_at'] = @app.updated_at || @app.created_at
        hash
      end

      def stop_index(index)
        Client.stop_indices(@app, [index])
      end
    end
  end
end
