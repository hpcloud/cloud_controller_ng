require "steno/codec/text"

class BackgroundJobEnvironment
  def initialize(config)
    @config = config
    VCAP::CloudController::StenoConfigurer.new(config[:logging]).configure do |steno_config_hash|
      steno_config_hash[:sinks] = [Steno::Sink::IO.new(STDOUT)]
      steno_config_hash[:codec] = Steno::Codec::Text.new
      steno_config_hash[:context] = Steno::Context::ThreadLocal.new
    end
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

        # The AppObserver need no knowledge of the DEA or stager pools
        # so we are passing in no-op objects for these arguments
        no_op_staging_pool = Object.new
        no_op_dea_pool = Object.new
        health_manager_client = CloudController::DependencyLocator.instance.health_manager_client

        backends = VCAP::CloudController::StackatoBackends.new(@config, message_bus, no_op_dea_pool, no_op_staging_pool, health_manager_client)
        VCAP::CloudController::AppObserver.configure(backends)

        blobstore_url_generator = CloudController::DependencyLocator.instance.blobstore_url_generator
        docker_registry = CloudController::DependencyLocator.instance.docker_registry
        VCAP::CloudController::Dea::Client.configure(@config, message_bus, no_op_dea_pool, no_op_staging_pool, blobstore_url_generator, docker_registry)
      end
    end
  end
end
