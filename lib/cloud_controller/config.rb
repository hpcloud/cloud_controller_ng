require "steno"
require "vcap/config"
require "cloud_controller/account_capacity"
require "cloud_controller/health_manager_client"
require "uri"
require 'kato/config'
require "cloud_controller/diego/traditional/staging_completion_handler"

# Config template for cloud controller
module VCAP::CloudController
  # rubocop:disable ClassLength
  class Config < VCAP::Config
    define_schema do
      {
        :port => Integer,
        :instance_socket => String,
        :external_port => Integer,
        :external_protocol => String,
        :info => {
          :name            => String,
          :build           => String,
          :version         => Fixnum,
          :support_address => String,
          :description     => String,
        },

        :system_domain => String,
        # Not creating default org-- done by first user setup (disabled in 67a488b98c)
        #:system_domain_organization => enum(String, NilClass),
        :app_domains => [ String ],
        :app_events => {
          :cutoff_age_in_days => Fixnum
        },
        :app_usage_events => {
          :cutoff_age_in_days => Fixnum
        },
        :audit_events => {
          :cutoff_age_in_days => Fixnum
        },
        :failed_jobs => {
          :cutoff_age_in_days => Fixnum
        },
        optional(:billing_event_writing_enabled) => bool,
        :default_app_memory => Fixnum,
        :default_app_disk_in_mb => Fixnum,
        optional(:maximum_app_disk_in_mb) => Fixnum,
        :maximum_health_check_timeout => Fixnum,

        optional(:allow_debug) => bool,

        optional(:login) => {
          :url      => String
        },

        :uaa => {
          :url                => String,
          :resource_id        => String,
          optional(:symmetric_secret)   => String
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
          :auth_user  => String,
          :auth_password => String,
        },

        :staging => {
          :timeout_in_seconds => Fixnum,
          optional(:minimum_staging_memory_mb) => Fixnum,
          optional(:minimum_staging_disk_mb) => Fixnum,
          :auth => {
            :user => String,
            :password => String,
          }
        },

        :cc_partition => String,

        optional(:default_account_capacity) => {
          :memory   => Fixnum,   #:default => 2048,
          :app_uris => Fixnum, #:default => 4,
          :services => Fixnum, #:default => 16,
          :apps     => Fixnum, #:default => 20
        },

        optional(:admin_account_capacity) => {
          :memory   => Fixnum,   #:default => 2048,
          :app_uris => Fixnum, #:default => 4,
          :services => Fixnum, #:default => 16,
          :apps     => Fixnum, #:default => 20
        },

        optional(:index)       => Integer,    # Component index (cc-0, cc-1, etc)
        optional(:name)        => String,     # Component name (api_z1, api_z2)
        optional(:local_route) => String,     # If set, use this to determine the IP address that is returned in discovery messages

        :nginx => {
          :use_nginx => bool
        },

        :stackato_upload_handler => {
          :enabled => bool
        },

        :quota_definitions => Hash,
        :default_quota_definition => String,

        :security_group_definitions => [
          {
            "name" => String,
            "rules" => [
              {
                "protocol" => String,
                "destination" => String,
                optional("ports") => String,
                optional("type") => Integer,
                optional("code") => Integer
              }
            ]
          }
        ],
        :default_staging_security_groups => [String],
        :default_running_security_groups => [String],

        :resource_pool => {
          optional(:maximum_size) => Integer,
          optional(:minimum_size) => Integer,
          optional(:resource_directory_key) => String,
          :fog_connection => Hash
        },

        :packages => {
          optional(:max_package_size) => Integer,
          optional(:app_package_directory_key) => String,
          :fog_connection => Hash
        },

        :droplets => {
          optional(:droplet_directory_key) => String,
          :fog_connection => Hash
        },

        :db_encryption_key => String,

        optional(:flapping_crash_count_threshold) => Integer,

        optional(:varz_port) => Integer,
        optional(:varz_user) => String,
        optional(:varz_password) => String,
        optional(:disable_custom_buildpacks) => bool,
        optional(:broker_client_timeout_seconds) => Integer,
        optional(:uaa_client_name) => String,
        optional(:uaa_client_secret) => String,
        optional(:uaa_client_scope) => String,

        :renderer => {
          :max_results_per_page => Integer,
          :default_results_per_page => Integer,
        },

        optional(:loggregator) => {
          optional(:router) => String,
          optional(:shared_secret) => String,
        },

        optional(:request_timeout_in_seconds) => Integer,
        optional(:skip_cert_verify) => bool,

        optional(:install_buildpacks) => [
          {
            "name" => String,
            optional("package") => String,
            optional("file") => String,
            optional("enabled") => bool,
            optional("locked") => bool,
            optional("position") => Integer,
          }
        ],

        optional(:app_bits_upload_grace_period_in_seconds) => Integer,
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

      attr_reader :config, :message_bus

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
        stager_pool = Dea::StagerPool.new(@config, message_bus)
        dea_pool = Dea::Pool.new(message_bus)
        dependency_locator = CloudController::DependencyLocator.instance

        blobstore_url_generator = dependency_locator.blobstore_url_generator

        diego_client = dependency_locator.diego_client
        diego_client.connect!

        diego_messenger = dependency_locator.diego_messenger

        Dea::Client.configure(@config, message_bus, dea_pool, stager_pool, blobstore_url_generator)

        Diego::Traditional::StagingCompletionHandler.new(message_bus, diego_messenger).subscribe!

        backends = StackatoBackends.new(@config, message_bus, dea_pool, stager_pool, health_manager_client)
        AppObserver.configure(backends)

        LegacyBulk.configure(@config, message_bus)

        BulkApi.configure(@config)
      end

      def config_dir
        @config_dir ||= File.expand_path("../../../config", __FILE__)
      end

      def run_initializers(config)
        return if @initialized
        run_initializers_in_directory(config, '../../../config/initializers/*.rb')
        if config[:newrelic_enabled]
          require "newrelic_rpm"
          run_initializers_in_directory(config, '../../../config/newrelic/initializers/*.rb')
        end
        @initialized = true
      end

      def run_initializers_in_directory(config, path)
        Dir.glob(File.expand_path(path, __FILE__)).each do |file|
          require file
          method = File.basename(file).sub(".rb", "").gsub("-", "_")
          CCInitializers.send(method, config)
        end
      end

      def merge_defaults(config)
        config[:stacks_file] ||= File.join(config_dir, "stacks.yml")
        config[:maximum_app_disk_in_mb] ||= 2048
        config[:request_timeout_in_seconds] ||= 300
        config[:directories] ||= {}
        config[:billing_event_writing_enabled] = true if config[:billing_event_writing_enabled].nil?
        config[:skip_cert_verify] = false if config[:skip_cert_verify].nil?
        config[:app_bits_upload_grace_period_in_seconds] ||= 0
        config[:db] ||= {}
        config[:db][:database] ||= ENV["DB_CONNECTION_STRING"]
        sanitize(config)
      end

      private

      def health_manager_client
        CloudController::DependencyLocator.instance.health_manager_client
      end

      def sanitize(config)
        grace_period = config[:app_bits_upload_grace_period_in_seconds]
        config[:app_bits_upload_grace_period_in_seconds] = 0 if grace_period < 0
        config
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
