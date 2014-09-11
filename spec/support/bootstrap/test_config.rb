require "support/bootstrap/db_config"
require "support/paths"

module TestConfig
  def self.override(overrides)
    @config = load(overrides)
  end

  # Returns true if the AUTOMATED_BUILD env-var is set and we are running in a CI instance.
  def self.automated_build?
    ENV['AUTOMATED_BUILD']
  end

  def self.reset
    TestConfig.override({})
  end

  def self.config
    @config ||= load
  end

  def self.load(overrides={})
    config = defaults.merge(overrides)
    config_yaml = automated_build? ? yaml_config(File.join(Paths::CONFIG, 'cloud_controller.yml')) : kato_config
    config_hash = ::Kato::Util.symbolize_keys(config_yaml)

    config_override = {
      :db => {
        :log_level => "debug",
        :database_uri => db_connection_string,
        :pool_timeout => 10
      },
      :directories => {
      },
    }

    config_hash.merge!(config_override || {})
    configure_components(config_hash)
    config_hash
  end
  
  def self.aok_config
    config_yaml = automated_build? ? yaml_config(nil) : kato_config('aok')
    config_hash = ::Kato::Util.symbolize_keys(config_yaml)
    return config_hash
  end

  def self.configure_components(config)
    # Always enable Fog mocking (except when using a local provider, which Fog can't mock).
    res_pool_connection_provider = config[:resource_pool][:fog_connection][:provider].downcase
    packages_connection_provider = config[:packages][:fog_connection][:provider].downcase
    Fog.mock! unless (res_pool_connection_provider == "local" || packages_connection_provider == "local")

    # DO NOT override the message bus, use the same mock that's set the first time
    message_bus = VCAP::CloudController::Config.message_bus || CfMessageBus::MockMessageBus.new

    VCAP::CloudController::Config.configure_components(config)
    VCAP::CloudController::Config.configure_components_depending_on_message_bus(message_bus)
    # reset the dependency locator
    CloudController::DependencyLocator.instance.send(:initialize)

    stacks_file = File.join(Paths::FIXTURES, "config/stacks.yml")
    VCAP::CloudController::Stack.configure(stacks_file)
    VCAP::CloudController::Stack.populate
  end

  def self.kato_config(component = "cloud_controller_ng")
    config_yaml = `kato config get #{component} --yaml`.strip
    if config_yaml != ""
      return YAML.load(config_yaml)
    else
      return {}
    end
  end

  # Loads config from a given filepath, used during automated testing where loading via kato isn't possible
  def self.yaml_config(filepath)
    if filepath.nil?
      {}
    else
      return YAML.load_file(filepath)
    end
  end

  def self.defaults
    config_file = File.join(Paths::CONFIG, "cloud_controller.yml")
    config_hash = VCAP::CloudController::Config.from_file(config_file)

    config_hash.update(
        :nginx => {:use_nginx => true},
        :resource_pool => {
            :resource_directory_key => "spec-cc-resources",
            :fog_connection => {
                :provider => "AWS",
                :aws_access_key_id => "fake_aws_key_id",
                :aws_secret_access_key => "fake_secret_access_key",
            },
        },
        :packages => {
            :app_package_directory_key => "cc-packages",
            :fog_connection => {
                :provider => "AWS",
                :aws_access_key_id => "fake_aws_key_id",
                :aws_secret_access_key => "fake_secret_access_key",
            },
        },
        :droplets => {
            :droplet_directory_key => "cc-droplets",
            :fog_connection => {
                :provider => "AWS",
                :aws_access_key_id => "fake_aws_key_id",
                :aws_secret_access_key => "fake_secret_access_key",
            },
        },

        :db => DbConfig.config
    )

    config_hash
  end
  
  def self.kato_config_preload
    ::Kato::Config.set("cluster", "endpoint", "api.example.com", { :force => true })
    ::Kato::Config.set("cloud_controller_ng", '/', self.config)
    config = ::Kato::Config.get("cloud_controller_ng")
    if !config[:quota_definitions] || !config['quota_definitions']
      config[:quota_definitions] = { :default => {
          :memory_limit => 2048,
          :total_services => 100,
          :non_basic_services_allowed => true,
          :total_routes => 1000,
          :trial_db_allowed => true,
          allow_sudo: false,
        }}
      ::Kato::Config.set("cloud_controller_ng", 'quota_definitions', config[:quota_definitions])
    end
    if !config[:droplets_to_keep] || !config['droplets_to_keep']
      config[:droplets_to_keep] = 5
      ::Kato::Config.set("cloud_controller_ng", 'droplets_to_keep',
                         config[:droplets_to_keep])
    end
    ::VCAP::CloudController::Config.configure_components(config)
    ::Kato::Config.set("aok", '/', aok_config)
    ::Kato::Config.set("dea_ng", '/', { :staging =>
                         { :disk_limit_mb => 2048 }})
    ::VCAP::CloudController::RestController::PreloadedObjectSerializer::configure(config)
  end
  
  def self.db_connection_string
    if ENV["DB_CONNECTION"]
      "#{ENV["DB_CONNECTION"]}/cc_test_#{ENV["TEST_ENV_NUMBER"]}"
    else
      "sqlite:///tmp/cc_test#{ENV["TEST_ENV_NUMBER"]}.db"
    end
  end
end
