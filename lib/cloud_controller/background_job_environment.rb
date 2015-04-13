require 'steno/codec/text'

class BackgroundJobEnvironment
  def initialize(config)
    @config = config
    @log_counter = Steno::Sink::Counter.new

    VCAP::CloudController::StenoConfigurer.new(config[:logging]).configure do |steno_config_hash|
	  steno_config_hash[:sinks] << @log_counter
      steno_config_hash[:codec] = Steno::Codec::Text.new
      steno_config_hash[:context] = Steno::Context::ThreadLocal.new
    end
  end

  def setup_environment
    VCAP::CloudController::DB.load_models(@config.fetch(:db), Steno.logger('cc.background'))
    VCAP::CloudController::Config.configure_components(@config)

    Thread.new do
      EM.run do
        message_bus = MessageBus::Configurer.new(
          servers: @config[:message_bus_servers],
          logger: Steno.logger('cc.message_bus')).go

        # The AppObserver need no knowledge of the DEA or stager pools
        # so we are passing in no-op objects for these arguments
        no_op_staging_pool = Object.new
        no_op_dea_pool = Object.new
        health_manager_client = CloudController::DependencyLocator.instance.health_manager_client

        runners = VCAP::CloudController::StackatoRunners.new(@config, message_bus, no_op_dea_pool, no_op_staging_pool, health_manager_client)
        stagers = VCAP::CloudController::StackatoStagers.new(@config, message_bus, no_op_dea_pool, no_op_staging_pool, runners)
        runners.stagers = stagers
        VCAP::CloudController::AppObserver.configure(stagers, runners)

        blobstore_url_generator = CloudController::DependencyLocator.instance.blobstore_url_generator
        docker_registry = CloudController::DependencyLocator.instance.docker_registry
        VCAP::CloudController::Dea::Client.configure(@config, message_bus, no_op_dea_pool, no_op_staging_pool, blobstore_url_generator, docker_registry)
      end
    end
  end
end
