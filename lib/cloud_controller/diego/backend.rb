module VCAP::CloudController
  module Diego
    class Backend
      def initialize(app, diego_client)
        @app = app
        @diego_client = diego_client
      end

      def requires_restage?
        # The DEA staging process doesn't know to set the start command, this happens
        # when an existing DEA based app is switched over to running on Diego
        @app.detected_start_command.empty?
      end

      def stage
       @diego_client.send_stage_request(@app)
      end

      def scale
        @diego_client.send_desire_request(@app)
      end

      def start(_={})
        @diego_client.send_desire_request(@app)
      end

      def stop
        @diego_client.send_desire_request(@app)
      end
    end
  end
end
