require 'steno'
require 'vcap/config'
require 'cloud_controller/account_capacity'
require 'uri'
require 'cloud_controller/health_manager_client'
require 'kato/config'
require 'cloud_controller/backends/stagers'
require 'cloud_controller/backends/runners'
require 'cloud_controller/index_stopper'
require 'cloud_controller/backends/instances_reporters'
require 'repositories/services/event_repository'

# Config template for cloud controller
module VCAP::CloudController
  # rubocop:disable ClassLength
  class Config < VCAP::Config
    define_schema do
      {
        :port => Integer,
        :external_port => Integer,
        :external_protocol => String,
        :info => {
          name: String,
          build: String,
          version: Fixnum,
          support_address: String,
          description: String,
        },

        :system_domain => String,
        # Not creating default org-- done by first user setup (disabled in 67a488b98c)
        #:system_domain_organization => enum(String, NilClass),
        :app_domains => [ String ],
        :app_events => {
          cutoff_age_in_days: Fixnum
        },
        :app_usage_events => {
          cutoff_age_in_days: Fixnum
        },
        :audit_events => {
          cutoff_age_in_days: Fixnum
        },
        :failed_jobs => {
          cutoff_age_in_days: Fixnum
        },
        optional(:billing_event_writing_enabled) => bool,
        :default_app_memory => Fixnum,
        :default_app_disk_in_mb => Fixnum,
        optional(:maximum_app_disk_in_mb) => Fixnum,
        :default_health_check_timeout => Fixnum,
        :maximum_health_check_timeout => Fixnum,

        optional(:instance_file_descriptor_limit) => Fixnum,

        optional(:allow_debug) => bool,

        optional(:login) => {
          url: String
        },

        :hm9000 => {
          url: String
        },

        :uaa => {
          :url                => String,
          :resource_id        => String,
          optional(:symmetric_secret)   => String,
        },

        :logging => {
          :level              => String,      # debug, info, etc.
          optional(:file)     => String,      # Log file to use
          optional(:syslog)   => String,      # Name to associate with syslog messages (should start with 'vcap.')
        },

        :message_bus_servers   => [String],   # A list of NATS uris of the form nats://<user>:<pass>@<host>:<port>
        :pid_filename          => String,     # Pid filename to use

        optional(:directories) => {
          optional(:tmpdir)    => String,
          optional(:diagnostics) => String,
        },

        optional(:stacks_file) => String,
        optional(:newrelic_enabled) => bool,

        optional(:db) => {
          optional(:database_uri) => String, # db connection string for sequel
          optional(:database) => {
            :host => String,
            :port => Integer,
            :user => String,
            :password => String,
            :adapter => String,
            :database => String,     # db connection string for sequel
          },
          optional(:log_level)        => String,     # debug, info, etc.
          optional(:max_connections)  => Integer,    # max connections in the connection pool
          optional(:pool_timeout)     => Integer     # timeout before raising an error when connection can't be established to the db
        },

        :bulk_api => {
          auth_user: String,
          auth_password: String,
        },

        :internal_api => {
          auth_user: String,
          auth_password: String,
        },

        :staging => {
          :timeout_in_seconds => Fixnum,
          optional(:minimum_staging_memory_mb) => Fixnum,
          optional(:minimum_staging_disk_mb) => Fixnum,
          optional(:minimum_staging_file_descriptor_limit) => Fixnum,
          :auth => {
            user: String,
            password: String,
          }
        },

        :cc_partition => String,

        optional(:default_account_capacity) => {
          memory: Fixnum,   #:default => 2048,
          app_uris: Fixnum, #:default => 4,
          services: Fixnum, #:default => 16,
          apps: Fixnum, #:default => 20
        },

        optional(:admin_account_capacity) => {
          memory: Fixnum,   #:default => 2048,
          app_uris: Fixnum, #:default => 4,
          services: Fixnum, #:default => 16,
          apps: Fixnum, #:default => 20
        },

        optional(:index)       => Integer,    # Component index (cc-0, cc-1, etc)
        optional(:name)        => String,     # Component name (api_z1, api_z2)
        optional(:local_route) => String,     # If set, use this to determine the IP address that is returned in discovery messages

        :nginx => {
          use_nginx: bool,
          instance_socket: String,
        },

        :stackato_upload_handler => {
          :enabled => bool
        },

        :quota_definitions => Hash,
        :default_quota_definition => String,

        :security_group_definitions => [
          {
            'name' => String,
            'rules' => [
              {
                'protocol' => String,
                'destination' => String,
                optional('ports') => String,
                optional('type') => Integer,
                optional('code') => Integer
              }
            ]
          }
        ],
        :default_staging_security_groups => [String],
        :default_running_security_groups => [String],

        :resource_pool => {
          optional(:maximum_size) => Integer,
          optional(:minimum_size) => Integer,
          :resource_directory_key => String,
          :fog_connection => Hash
        },

        :packages => {
          optional(:max_package_size) => Integer,
          :app_package_directory_key => String,
          :fog_connection => Hash
        },

        :droplets => {
          droplet_directory_key: String,
          fog_connection: Hash
        },

        :db_encryption_key => String,

        optional(:flapping_crash_count_threshold) => Integer,

        optional(:varz_port) => Integer,
        optional(:varz_user) => String,
        optional(:varz_password) => String,
        optional(:disable_custom_buildpacks) => bool,
        optional(:broker_client_timeout_seconds) => Integer,
        optional(:broker_client_default_async_poll_interval_seconds) => Integer,
        optional(:broker_client_max_async_poll_attempts) => Integer,
        optional(:uaa_client_name) => String,
        optional(:uaa_client_secret) => String,
        optional(:uaa_client_scope) => String,

        optional(:cloud_controller_username_lookup_client_name) => String,
        optional(:cloud_controller_username_lookup_client_secret) => String,

        :renderer => {
          max_results_per_page: Integer,
          default_results_per_page: Integer,
        },

        optional(:loggregator) => {
          optional(:router) => String,
          optional(:shared_secret) => String,
        },

        optional(:request_timeout_in_seconds) => Integer,
        optional(:skip_cert_verify) => bool,

        optional(:install_buildpacks) => [
          {
            'name' => String,
            optional('package') => String,
            optional('file') => String,
            optional('enabled') => bool,
            optional('locked') => bool,
            optional('position') => Integer,
          }
        ],

        optional(:app_bits_upload_grace_period_in_seconds) => Integer,

        optional(:default_locale) => String,
        optional(:allowed_cors_domains) => [String],

        optional(:dea_advertisement_timeout_in_seconds) => Integer,

        optional(:diego_docker) => bool,
        optional(:diego_tps_url) => String,
        optional(:users_can_select_backend) => bool,
        optional(:default_to_diego_backend) => bool,
      }
    end

    class << self

      def logger
        @logger ||= Steno.logger("cc.config")
      end

      def from_file(file_name)
        config = super(file_name)
        merge_defaults(config)
        apply_stackato_overrides(config)
      end

      def from_redis(config_overrides = {})
        config = Kato::Config.get("cloud_controller_ng").symbolize_keys
        config.update(config_overrides)
        merge_defaults(config)
        validate_upgraded_config(config)
        apply_stackato_overrides(config)
      end

      attr_reader :config, :message_bus, :backends

      # Performs validation on the cc_ng config to make sure that any config values sitting under old keys (from previous
      # versions of the cc_ng component) that haven't been updated to their newer counterpart after an upgrade get updated
      # before the cc_ng starts up.
      # xxx: This doesn't remove the old values as they could be required by other cc_ngs still being upgraded
      def validate_upgraded_config(config)
        # v3.0.1 message_bus_uri: String -> v3.2.1 message_bus_servers: [String]
        if config[:message_bus_uri]
          if config[:message_bus_servers] && config[:message_bus_servers] == ['nats://127.0.0.1:4222']
            config[:message_bus_servers] = [config[:message_bus_uri]]
            Kato::Config.set('cloud_controller_ng', 'message_bus_servers', config[:message_bus_servers])
          end
        end

        config
      end

      def configure_components(config)
        @config = config

        # TODO:Stackato: Re-enable config watcher
        config_watch(config)

        Encryptor.db_encryption_key = config[:db_encryption_key]
        AccountCapacity.configure(config)
        ResourcePool.instance = ResourcePool.new(config)

        QuotaDefinition.configure(config)
        Stack.configure(config[:stacks_file])

        run_initializers(config)
      end

      def configure_components_depending_on_message_bus(message_bus)
        @message_bus = message_bus
        dependency_locator = CloudController::DependencyLocator.instance
        dependency_locator.config = @config
        if @config[:hm9000_noop]
          hm_client = HealthManagerClient.new(@message_bus, @config)
        else
          legacy_hm_client = Dea::HM9000::LegacyClient.new(@message_bus, @config)
          hm_client = Dea::HM9000::Client.new(legacy_hm_client, @config)
        end
        dependency_locator.register(:health_manager_client, hm_client)
        diego_client = Diego::Client.new(@config)
        dependency_locator.register(:diego_client, diego_client)
        dependency_locator.register(:upload_handler, UploadHandler.new(config))
        dependency_locator.register(:app_event_repository, Repositories::Runtime::AppEventRepository.new)

        blobstore_url_generator = dependency_locator.blobstore_url_generator
        docker_registry = dependency_locator.docker_registry
        stager_pool = Dea::StagerPool.new(@config, message_bus, blobstore_url_generator)
        dea_pool = Dea::Pool.new(@config, message_bus)
        runners = StackatoRunners.new(@config, message_bus, dea_pool, stager_pool, health_manager_client)
        stagers = StackatoStagers.new(@config, message_bus, dea_pool, stager_pool, runners)
        runners.stagers = stagers

        dependency_locator.register(:stagers, stagers)
        dependency_locator.register(:runners, runners)
        dependency_locator.register(:instances_reporters, InstancesReporters.new(diego_client, hm_client))
        dependency_locator.register(:index_stopper, IndexStopper.new(runners))

        Dea::Client.configure(@config, message_bus, dea_pool, stager_pool, blobstore_url_generator, docker_registry)

        AppObserver.configure(stagers, runners)

        LegacyBulk.configure(@config, message_bus)

        InternalApi.configure(@config)
      end

      def config_dir
        @config_dir ||= File.expand_path('../../../config', __FILE__)
      end

      def run_initializers(config)
        return if @initialized
        run_initializers_in_directory(config, '../../../config/initializers/*.rb')
        if config[:newrelic_enabled]
          require 'newrelic_rpm'
          run_initializers_in_directory(config, '../../../config/newrelic/initializers/*.rb')
        end
        @initialized = true
      end

      def run_initializers_in_directory(config, path)
        Dir.glob(File.expand_path(path, __FILE__)).each do |file|
          require file
          method = File.basename(file).sub('.rb', '').gsub('-', '_')
          CCInitializers.send(method, config)
        end
      end

      def merge_defaults(config)
        config[:stacks_file] ||= File.join(config_dir, 'stacks.yml')
        config[:maximum_app_disk_in_mb] ||= 2048
        config[:request_timeout_in_seconds] ||= 900
        config[:directories] ||= {}
        config[:billing_event_writing_enabled] = true if config[:billing_event_writing_enabled].nil?
        config[:skip_cert_verify] = false if config[:skip_cert_verify].nil?
        config[:app_bits_upload_grace_period_in_seconds] ||= 0
        config[:db] ||= {}
        config[:db][:database] ||= ENV['DB_CONNECTION_STRING']
        config[:default_locale] ||= 'en_US'
        config[:allowed_cors_domains] ||= []
        config[:diego_docker] ||= false
        config[:default_to_diego_backend] ||= false
        config[:dea_advertisement_timeout_in_seconds] ||= 10
        config[:staging][:minimum_staging_memory_mb] ||= 1024
        config[:staging][:minimum_staging_disk_mb] ||= 4096
        config[:staging][:minimum_staging_file_descriptor_limit] ||= 16384
        config[:broker_client_timeout_seconds] ||= 60
        config[:broker_client_default_async_poll_interval_seconds] ||= 60

        unless config.key?(:users_can_select_backend)
          config[:users_can_select_backend] = true
        end

        sanitize(config)
      end

      private

      def health_manager_client
        CloudController::DependencyLocator.instance.health_manager_client
      end

      def sanitize(config)
        sanitize_grace_period(config)
        sanitize_staging_auth(config)
        config
      end

      def sanitize_grace_period(config)
        grace_period = config[:app_bits_upload_grace_period_in_seconds]
        config[:app_bits_upload_grace_period_in_seconds] = 0 if grace_period < 0
      end

      def sanitize_staging_auth(config)
        auth = config[:staging][:auth]
        auth[:user] = escape_userinfo(auth[:user]) unless valid_in_userinfo?(auth[:user])
        auth[:password] = escape_userinfo(auth[:password]) unless valid_in_userinfo?(auth[:password])
      end

      def escape_userinfo(value)
        URI.escape(value, "%#{URI::REGEXP::PATTERN::RESERVED}")
      end

      def valid_in_userinfo?(value)
        URI::REGEXP::PATTERN::USERINFO.match(value)
      end

      def config_watch(config)
        Kato::Config.watch "cloud_controller_ng" do |new_config|
          new_config = new_config.symbolize_keys
          updates = Kato::Config.diff(@config, new_config)
          updates.each do |update|
            # TODO: Currently blankly ignoring deletions, due to
            #       additions added to AppConfig by CC runtime.
            #       Better handle deletions.
            next if update[:del]

            logger.debug("Config update : #{update[:path]} = #{update[:value]}")

            begin

              # default_account_capacity
              if match = update[:path].match("^/((?:default|admin)_account_capacity)/(memory|app_uris|services|apps)$")
                key = match[1]
                limit_type = match[2]
                limit = update[:value]
                logger.debug("Updating AccountCapacity #{key} #{limit_type} = #{limit}")
                AccountCapacity.configure({
                  key => {
                    limit_type => limit
                  } 
                })
              end

              # logging
              if update[:path] == "/logging/level"
                logger.warn("Changing logging level to '#{update[:value]}'")
                Steno.set_logger_regexp(/.+/, update[:value].to_sym)
              end

            rescue Exception => e
              raise "Failed to update in-memory config for #{update[:path]} = #{update[:value]} " + e.message
            end
          end
          if updates.size > 0
            # XXX: This might blitz some changes by CC runtime.
            #      Change CC to not save in-process state in config.
            config.merge!(new_config)
            apply_stackato_overrides(config)
          end
        end
      end

      def apply_stackato_overrides(config)
        if config.fetch(:nginx, {}).fetch(:use_nginx, false)
          # logging is unavailable at this point
          puts "Stackato does not support nginx/use_nginx; disabling it."
          config[:nginx][:use_nginx] = false
        end

        config
      end

    end
  end
end
