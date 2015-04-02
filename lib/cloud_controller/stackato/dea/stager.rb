require 'cloud_controller/dea/stager'

module VCAP::CloudController
  module Dea
    class StackatoStager < Stager

      def stage_app
        blobstore_url_generator = CloudController::DependencyLocator.instance.blobstore_url_generator
        task = StackatoAppStagerTask.new(@config, @message_bus, @app, @dea_pool, @stager_pool, blobstore_url_generator)

        @app.last_stager_response = task.stage do |staging_result|
          @runners.runner_for_app(@app).start(staging_result)
        end
      end
    end
  end
end
