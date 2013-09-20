require "steno"
require "vcap/config"
require "cloud_controller/account_capacity"
require "uri"
require 'kato/config'

# Config template for cloud controller
module VCAP::CloudController
  class Config < VCAP::Config
    define_schema do
      {
        :port => Integer,
        :info => {
          :name            => String,
          :build           => String,
          :version         => Fixnum,
          :support_address => String,
          :description     => String,
        },

        :system_domain => String,
        :system_domain_organization => enum(String, NilClass),
        :app_domains => [ String ],

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

        :message_bus_uri              => String,     # Currently a NATS uri of the form nats://<user>:<pass>@<host>:<port>
        :pid_filename          => String,     # Pid filename to use

        optional(:directories) => {
          optional(:tmpdir)    => String,
          optional(:droplets)  => String,
          optional(:staging_manifests) => String,
        },

        optional(:stacks_file) => String,

        :db => {
          optional(:database_uri) => String, # db connection string for sequel
          optional(:database) => {
            :host => String,
            :port => Integer,
            :user => String,
            :password => String,
            :adapter => String,
            :database => String
          },
          optional(:log_level)        => String,     # debug, info, etc.
          optional(:max_connections)  => Integer,    # max connections in the connection pool
          optional(:pool_timeout)     => Integer     # timeout before raising an error when connection can't be established to the db
        },

        :bulk_api => {
          :auth_user  => String,
          :auth_password => String,
        },

        :cc_partition => String,

        # TODO: use new defaults to set these defaults
        optional(:default_account_capacity) => {
          :memory   => Fixnum,   #:default => 2048,
          :app_uris => Fixnum, #:default => 4,
          :services => Fixnum, #:default => 16,
          :apps     => Fixnum, #:default => 20
        },

        # TODO: use new defaults to set these defaults
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
          :use_nginx  => bool,
          :instance_socket => String,
        },

        :quota_definitions => Hash,
        :default_quota_definition => String,

        :resource_pool => {
          optional(:maximum_size) => Integer,
          optional(:minimum_size) => Integer,
          optional(:resource_directory_key) => String,
          :fog_connection => {
            :provider => String,
            optional(:aws_access_key_id) => String,
            optional(:aws_secret_access_key) => String,
            optional(:local_root) => String
          }
        },

        :packages => {
          optional(:max_droplet_size) => Integer,
          optional(:app_package_directory_key) => String,
          :fog_connection => {
            :provider => String,
            optional(:aws_access_key_id) => String,
            optional(:aws_secret_access_key) => String,
            optional(:local_root) => String
          }
        },

        :droplets => {
          optional(:max_droplet_size) => Integer,
          optional(:droplet_directory_key) => String,
          :fog_connection => {
            :provider => String,
            optional(:aws_access_key_id) => String,
            optional(:aws_secret_access_key) => String,
            optional(:local_root) => String
          }
        },

        :db_encryption_key => String,

        optional(:trial_db) => {
          :guid => String,
        },

        optional(:tasks_disabled) => bool
      }
    end

    def logger
      @logger ||= Steno.logger("cc.config")
    end

    def config_watch
      Kato::Config.watch "cloud_controller_ng" do |new_config|
        new_config = new_config.symbolize_keys
        updates = Kato::Config.diff(@config, new_config)
        updates.each do |update|
          # TODO: Currently blankly ignoring deletions, due to
          #       additions added to AppConfig by CC runtime.
          #       Better handle deletions.
          next if update[:del]

          self.logger.debug("Config update : #{update[:path]} = #{update[:value]}")

          begin

            # default_account_capacity
            if match = update[:path].match("^/(default)_account_capacity/([^/]+)")
              who = match[1]
              key = match[2]
              self.logger.debug("Updating AccountCapacity #{who} #{key} = #{update[:value]}")
              AccountCapacity.send(who)[key.to_sym] = update[:value]
            end

            # logging
            if update[:path] == "/logging/level"
              self.logger.warn("Changing logging level to '#{update[:value]}'")
              Steno.set_logger_regexp(/.+/, update[:value].to_sym)
            end

          rescue Exception => e
            raise "Failed to update in-memory config for #{update[:path]} = #{update[:value]} " + e.message
          end
        end
        if updates.size > 0
          # XXX: This might blitz some changes by CC runtime.
          #      Change CC to not use AppConfig for in-process
          #      state.
          @config.merge!(new_config)
        end
      end
    end

    class << self
      def from_file(file_name)
        config = super(file_name)
        merge_defaults(config)
      end

      def from_redis(config_overrides = {})
        config = Kato::Config.get("cloud_controller_ng").symbolize_keys
        config.update(config_overrides)
        merge_defaults(config)
      end

      attr_reader :config, :message_bus

      def configure(config)
        @config = config

        # TODO:Stackato: Re-enable config watcher
        #config_watch

        Config.db_encryption_key = config[:db_encryption_key]
        AccountCapacity.configure(config)
        ResourcePool.instance =
          ResourcePool.new(config)
        AppPackage.configure(config)

        StagingsController.configure(config)

        QuotaDefinition.configure(config)
        Stack.configure(config[:stacks_file])
        ServicePlan.configure(config[:trial_db])

        run_initializers(config)
      end

      def configure_message_bus(message_bus)
        @message_bus = message_bus

        stager_pool = StagerPool.new(@config, message_bus)

        AppObserver.configure(@config, message_bus, stager_pool)

        dea_pool = DeaPool.new(message_bus)

        DeaClient.configure(@config, message_bus, dea_pool)

        LegacyBulk.configure(@config, message_bus)
      end

      def run_initializers(config)
        return if @initialized

        Dir.glob(File.expand_path('../../../config/initializers/*.rb', __FILE__)).each do |file|
          require file
          method = File.basename(file).sub(".rb", "").gsub("-", "_")
          CCInitializers.send(method, config)
        end
        @initialized = true
      end

      attr_accessor :db_encryption_key

      def config_dir
        @config_dir ||= File.expand_path("../../../config", __FILE__)
      end

      private

      def merge_defaults(config)
        config[:stacks_file] ||= File.join(config_dir, "stacks.yml")

        config[:directories] ||= {}
        config[:directories][:staging_manifests] ||= File.join(config_dir, "frameworks")
        config
      end
    end
  end
end
