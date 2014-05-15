require "steno/codec/text"

class BackgroundJobEnvironment
  def initialize(config)
    @config = config
    Steno.init(Steno::Config.new(:sinks => [Steno::Sink::IO.new(STDOUT)],
                                 :codec => Steno::Codec::Text.new))
  end

  def setup_environment
    logger = Steno.logger("cc.background")
    VCAP::CloudController::DB.load_models(@config.fetch(:db), logger)
    VCAP::CloudController::Config.configure_components(@config)

    Thread.new do
      EM.run do
        message_bus = MessageBus::Configurer.new(
          :servers => @config[:message_bus_servers],
          :logger => Steno.logger("cc.message_bus")).go
        no_op_staging_pool = Object.new
        health_manager_client = VCAP::CloudController::HealthManagerClient.new(message_bus)
        VCAP::CloudController::AppObserver.configure(@config, message_bus, no_op_staging_pool, health_manager_client)
      end
    end
  end
end
