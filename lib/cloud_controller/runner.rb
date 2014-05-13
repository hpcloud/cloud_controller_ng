require "steno"
require "steno/codec/text"
require "optparse"
require "vcap/uaa_token_decoder"
require "vcap/uaa_verification_key"
require "cf_message_bus/message_bus"
require "cf/registrar"
require "loggregator_emitter"
require "loggregator"
<<<<<<< HEAD
require 'kato/local/node'
require "kato/proc_ready"
=======
require "cloud_controller/globals"
require "cloud_controller/rack_app_builder"
>>>>>>> upstream/master
require "cloud_controller/varz"

require_relative "seeds"
require_relative "message_bus_configurer"
require_relative "stackato/redis_client"
require_relative "stackato/app_logs_client"
require_relative "stackato/auto_scaler_respondent"
require_relative "stackato/deactivate_services"
require_relative "stackato/droplet_accountability"

module VCAP::CloudController
  class Runner
    attr_reader :config_file, :insert_seed_data

    def initialize(argv)
      @argv = argv

      # default to production. this may be overriden during opts parsing
      ENV["RACK_ENV"] = "production"
      parse_options!
      parse_config

      @log_counter = Steno::Sink::Counter.new
    end

    def logger
      @logger ||= Steno.logger("cc.runner")
    end

    def options_parser
      @parser ||= OptionParser.new do |opts|
        opts.on("-c", "--config [ARG]", "Configuration File") do |opt|
          @config_file = opt
        end

        opts.on("-m", "--run-migrations", "Actually it means insert seed data") do
          deprecation_warning "Deprecated: Use -s or --insert-seed flag"
          @insert_seed_data = true
        end

        opts.on("-s", "--insert-seed", "Insert seed data") do
          @insert_seed_data = true
        end
      end
    end

    def deprecation_warning(message)
      puts message
    end

    def parse_options!
      options_parser.parse! @argv
    rescue
      puts options_parser
      exit 1
    end

    def parse_config
      @config = VCAP::CloudController::Config.from_redis
    rescue Membrane::SchemaValidationError => ve
      puts "ERROR: There was a problem validating the supplied config: #{ve}"
      exit 1
    rescue => e
<<<<<<< HEAD
      exit 1
    end

    def setup_logging
      steno_config = Steno::Config.to_config_hash(@config[:logging])
      steno_config[:codec] = Steno::Codec::Text.new
      steno_config[:context] = Steno::Context::ThreadLocal.new
      steno_config[:sinks] << @log_counter
      Steno.init(Steno::Config.new(steno_config))
    end

    def setup_db
      logger.info "db config #{@config[:db]}"
      db_logger = Steno.logger("cc.db")
      DB.load_models(@config[:db], db_logger)
    end

    def setup_loggregator_emitter
      if @config[:loggregator] && @config[:loggregator][:router] && @config[:loggregator][:shared_secret]
        Loggregator.emitter = LoggregatorEmitter::Emitter.new(@config[:loggregator][:router], LogMessage::SourceType::CLOUD_CONTROLLER, @config[:index])
      end
    end

    def development_mode?
      @config[:development_mode]
    end

=======
      puts "ERROR: Failed loading config from file '#{@config_file}': #{e}"
      exit 1
    end

>>>>>>> upstream/master
    def run!
      EM.run do
        message_bus = MessageBus::Configurer.new(servers: @config[:message_bus_servers], logger: logger).go

        start_cloud_controller(message_bus)

        Seeds.write_seed_data(@config) if @insert_seed_data
        register_with_collector(message_bus)

        globals = Globals.new(@config, message_bus)
        globals.setup!

        builder = RackAppBuilder.new
        app = builder.build(@config)

<<<<<<< HEAD
        router_registrar.register_with_router
        ::Kato::ProcReady.i_am_ready("cloud_controller_ng")
=======
        start_thin_server(app)

        router_registrar.register_with_router

        VCAP::CloudController::Varz.setup_updates
>>>>>>> upstream/master
      end
    end

    def trap_signals
      %w(TERM INT QUIT).each do |signal|
        trap(signal) do
          logger.warn("Caught signal #{signal}")
          stop!
        end
      end

      trap('USR2') do
        logger.warn("Caught signal USR2")
        stop_router_registrar
      end
    end

    def stop!
      stop_router_registrar do
        stop_thin_server
        logger.info("Stopping EventMachine")
        EM.stop
      end
    end

    def merge_vcap_config
      services = JSON.parse(ENV["VCAP_SERVICES"])
      pg_key = services.keys.select { |svc| svc =~ /postgres/i }.first
      c = services[pg_key].first["credentials"]
      @config[:db][:database] = "postgres://#{c["user"]}:#{c["password"]}@#{c["hostname"]}:#{c["port"]}/#{c["name"]}"
      @config[:external_port] = ENV["VCAP_APP_PORT"].to_i
    end

    private

    def stop_router_registrar(&blk)
      logger.info("Unregistering routes.")
      router_registrar.shutdown(&blk)
    end

    def start_cloud_controller(message_bus)
      setup_logging
      setup_db
      Config.configure_components(@config)
      setup_loggregator_emitter

<<<<<<< HEAD
      @config[:bind_address] = Kato::Local::Node.get_local_node_id

=======
      @config[:external_host] = VCAP.local_ip(@config[:local_route])
>>>>>>> upstream/master
      Config.configure_components_depending_on_message_bus(message_bus)

      # TODO:Stackato: Move to CloudController::DependencyLocator ?
      EphemeralRedisClient::configure(@config)
      AppLogsRedisClient::configure(@config)
      StackatoAppLogsClient::configure(@config)
      StackatoDropletAccountability::configure(@config, message_bus)
      StackatoDropletAccountability::start
      StackatoDeactivateServices::start
    end

    def create_pidfile
      pid_file = VCAP::PidFile.new(@config[:pid_filename])
      pid_file.unlink_at_exit
    rescue
      puts "ERROR: Can't create pid file #{@config[:pid_filename]}"
      exit 1
    end

    def setup_logging
      StenoConfigurer.new(@config[:logging]).configure do |steno_config_hash|
        steno_config_hash[:sinks] << @log_counter
      end
    end

    def setup_db
      logger.info "db config #{@config[:db]}"
      db_logger = Steno.logger("cc.db")
      DB.load_models(@config[:db], db_logger)
    end

<<<<<<< HEAD
        VCAP::CloudController.auto_scaler_respondent = \
          VCAP::CloudController::AutoScalerRespondent.new(config, message_bus)
        VCAP::CloudController.auto_scaler_respondent.handle_requests

        map "/" do
          run Controller.new(config, token_decoder)
        end
      end
    end

    def start_thin_server(app, config)
      if @config[:nginx][:use_nginx] || @config[:stackato_upload_handler][:enabled]
        @thin_server = Thin::Server.new(
            config[:instance_socket],
            :signals => false
        )
=======
    def setup_loggregator_emitter
      if @config[:loggregator] && @config[:loggregator][:router] && @config[:loggregator][:shared_secret]
        Loggregator.emitter = LoggregatorEmitter::Emitter.new(@config[:loggregator][:router], "API", @config[:index], @config[:loggregator][:shared_secret])
      end
    end

    def start_thin_server(app)
      if @config[:nginx][:use_nginx]
        @thin_server = Thin::Server.new(@config[:nginx][:instance_socket], signals: false)
>>>>>>> upstream/master
      else
        @thin_server = Thin::Server.new(@config[:external_host], @config[:external_port])
      end

      @thin_server.app = app
      trap_signals

      # The routers proxying to us handle killing inactive connections.
      # Set an upper limit just to be safe.
      @thin_server.timeout = @config[:request_timeout_in_seconds]
      @thin_server.threaded = true
      @thin_server.start!
    end

    def stop_thin_server
      logger.info("Stopping Thin Server.")
      @thin_server.stop if @thin_server
    end

    def router_registrar
      @registrar ||= Cf::Registrar.new(
          message_bus_servers: @config[:message_bus_servers],
          host: @config[:external_host],
          port: @config[:external_port],
          uri: @config[:external_domain],
          tags: {:component => "CloudController"},
          index: @config[:index],
      )
    end

    def register_with_collector(message_bus)
      VCAP::Component.register(
          :type => 'CloudController',
          :host => @config[:external_host],
          :port => @config[:varz_port],
          :user => @config[:varz_user],
          :password => @config[:varz_password],
          :index => @config[:index],
          :nats => message_bus,
          :logger => logger,
          :log_counter => @log_counter
      )
    end
  end
end
