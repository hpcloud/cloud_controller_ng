module VCAP::CloudController
  module Dea
    module SubSystem
      def self.setup!(message_bus, config)
        Client.run

        LegacyBulk.register_subscription

        hm9000_respondent = (config[:hm9000_noop] ? HealthManagerRespondent : HM9000Client).new(Client, message_bus)
        hm9000_respondent.handle_requests

        dea_respondent = Respondent.new(message_bus)
        dea_respondent.start
        
        VCAP::CloudController.auto_scaler_respondent = \
            VCAP::CloudController::AutoScalerRespondent.new(config, message_bus)
        VCAP::CloudController.auto_scaler_respondent.handle_requests
      end
    end
  end
end
