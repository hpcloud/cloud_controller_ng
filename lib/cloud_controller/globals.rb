module VCAP::CloudController
  class Globals
    def initialize(config, message_bus)
      @config = config
      @message_bus = message_bus
    end

    def setup!
      DeaClient.run
      AppObserver.run

      LegacyBulk.register_subscription

      hm9000_respondent = (@config[:hm9000_noop] ? HealthManagerRespondent : HM9000Client).new(DeaClient, @message_bus)
      hm9000_respondent.handle_requests

      VCAP::CloudController.dea_respondent = DeaRespondent.new(@message_bus)
      VCAP::CloudController.dea_respondent.start

      VCAP::CloudController.auto_scaler_respondent = \
        VCAP::CloudController::AutoScalerRespondent.new(@config, @message_bus)
      VCAP::CloudController.auto_scaler_respondent.handle_requests
    end
  end
end
