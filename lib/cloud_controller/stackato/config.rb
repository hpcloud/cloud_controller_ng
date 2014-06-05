require 'kato/config'
require 'yaml'

module VCAP::CloudController
  class StackatoConfig
  
    ALL = "all"
    
    # Which config parameters are returned by the API.
    PERMISSIONS = YAML.load_file(File.join(File.dirname(__FILE__), "..", "..", "..", "config", "stackato", "config_permissions.yml"))["processes"]

    # These are the keys that are just set directly, without any additional logic
    SIMPLE_CASE = {
      "cloud_controller_ng" => [
        "maintenance_mode",
        "support_address"
      ],
      "dea_ng" => [
        "max_memory_percentage"
      ],
      "stager" => [
        "max_staging_duration"
      ],
      "harbor_node" => [
        "host_external",
        "hostname_external"
      ],
      "mongodb_node" => [
        "capacity"
      ],
      "mongodb_gateway" => [
        "allow_over_provisioning"
      ],
      "mysql_node" => [
        "capacity",
        "max_db_size"
      ],
      "mysql_gateway" => [
        "allow_over_provisioning"
      ],
      "postgresql_node" => [
        "capacity",
        "max_db_size"
      ],
      "postgresql_gateway" => [
        "allow_over_provisioning"
      ],
      "rabbit_node" => [
        "capacity",
        "max_memory"
      ],
      "rabbit3_node" => [
        "capacity",
        "max_memory"
      ],
      "rabbit_gateway" => [
        "allow_over_provisioning"
      ],
      "rabbit3_gateway" => [
        "allow_over_provisioning"
      ],
      "redis_node" => [
        "capacity",
        "max_memory"
      ],
      "redis_gateway" => [
        "allow_over_provisioning"
      ],
      "memcached_node" => [
        "capacity",
        "memcached_memory"
      ],
      "memcached_gateway" => [
        "allow_over_provisioning"
      ],
      "filesystem_gateway" => [
        "allow_over_provisioning"
      ],
      "filesystem_node" => [
        "capacity",
        "max_fs_size"
      ]
  
    }
  
    USERNAME_MIN_SIZE = 6
  
    attr_accessor :component_name
  
    def initialize(component_name)
      @component_name = component_name.to_s
    end

    def logger
      @logger ||= Steno.logger("cc.stackato.config")
    end

    def get_viewable
      component_config = get_component_config
      return nil unless component_config
      can_read, readable_config = filter_permissible_values(component_config, PERMISSIONS[@component_name], "R")
      readable_config
    end
  
    def filter_permissible_values(config, permissions, required_permission)
      if permissions.is_a? Hash
        filtered = {}
        config.each_pair do |key, value|
          key_permissions = permissions[key.to_s]
          next unless key_permissions
          if key_permissions.is_a? Hash
            can_read, new_value = filter_permissible_values(
              value,
              key_permissions,
              required_permission
            )
            filtered[key] = new_value if can_read
          elsif key_permissions.include? required_permission
            filtered[key] = value
          end
        end
        return true, filtered if filtered.size > 0
      end
      return false, nil
    end
  
    def save(new_config)
      if @component_name == ALL
        PERMISSIONS.keys.each do |component|
          save_for_component(component, new_config)
        end
      else
        save_for_component(@component_name, new_config)
      end
    end
    
    private
    
    def get_component_config
      config = Kato::Config.get(@component_name)
      config.symbolize_keys unless config.nil?
      config
    end
  
    def save_for_component(component_name, new_config)
      component_name = component_name.to_s
      can_write, writable_config = filter_permissible_values(new_config, PERMISSIONS[component_name], "W")
      unless can_write
        raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component_name, "Submitted non-writable config.")
      end
      unsupported_keys = new_config.keys - writable_config.keys
      if unsupported_keys.size > 0
        raise ::VCAP::Errors::StackatoConfigUnsupportedKeys.new(unsupported_keys)
      end
  
      writable_config.each do |key, value|
        key = key.to_s
        if SIMPLE_CASE[component_name] && SIMPLE_CASE[component_name].include?(key)
          simple_set(component_name, key, value)
        else
          update_method = nil
          if key == "logging"
            update_method = "_update__#{key}"
          else
            update_method = "_update__#{component_name}__#{key}"
          end
          method(update_method).call(component_name, key, value)
        end
      end
    end
    
    def simple_set component, key, value
      logger.info("Setting #{key} to #{value}")
      Kato::Config.set(component, key, value)
    end
  
    def _update__logging(component, key, logging)
      logging.each do |logging_key, logging_value|
        if logging_key == "level"
          log_level = logging_value 
          # Log levels taken from here
          # https://github.com/cloudfoundry/common/blob/master/vcap_logging/lib/vcap/logging.rb#L14
          unless %w{debug2 debug1 debug info warn error fatal off}.include? log_level
            raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component, "invalid logging level")
          end
          Kato::Config.set(component, "logging/level", log_level, { :must_exist => true })
        else
          logger.warn("Not updating #{component} #{key}/#{logging_key} to #{logging_value}")
        end
      end
    end

    def _update__dea_ng__resources(component, key, resources)
      unless resources.key? 'memory_max_percent'
        raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component, "Attempting to update #{component} resources with no valid key/value pairs!")
      end
      if resources.key? 'memory_max_percent'
        memory_max_percent = resources['memory_max_percent'].to_i
        logger.info("Setting #{component}/resources/memory_max_percent to #{memory_max_percent}")
        Kato::Config.set(component, "resources/memory_max_percent", memory_max_percent)
      end
    end
  
    def _update__dea_ng__timeouts(component, key, timeouts)
      if ( !(timeouts.key? "app_startup_port_ready"))
        raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component, "Attempting to update #{component} timeouts with no valid key/value pairs!")
      end
      if (timeouts.key? "app_startup_port_ready")
        app_startup_port_ready = timeouts["app_startup_port_ready"].to_i
        logger.info("Setting #{component}/timeouts/app_startup_port_ready to #{app_startup_port_ready}")
        Kato::Config.set(component, "timeouts/app_startup_port_ready", app_startup_port_ready)
      end
    end

    def _update__cloud_controller_ng__info(component, info_key, info)
      info.each do |key, value|
        Kato::Config.set(component, "#{info_key}/#{key}", value, { :must_exist => true })
      end
    end
  
    def _update__cloud_controller_ng__quota_definitions(component, definition_key, definitions)
      definitions.each do |key, value|
        Kato::Config.set(component, "#{definition_key}/#{key}", value, {:must_exist => true})
      end
    end
  
    def _update__harbor_node__port_range(component, key, port_range)
      if ( !(port_range.key? "min") && !(port_range.key? "max") )
        raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component, "Attempting to update port_range with no valid key/value pairs!")
      end
      current_min = Kato::Config.get("harbor_node", "port_range/min")
      current_max = Kato::Config.get("harbor_node", "port_range/max")
      if port_range.key? "min"
        port_range_min = port_range["min"].to_i
        if port_range_min < 1024 || port_range_min > 65535
          raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component, "Minimum port range must be between 1024 and 65535")
        end
        if port_range_min > current_max
          raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component, "Minimum port range must be an equal or lesser value than the current maximum port range of #{current_max}");
        end
        logger.info("Setting harbor_node/port_range/min to #{port_range_min}")
        Kato::Config.set("harbor_node", "port_range/min", port_range_min)
      end
      if port_range.key? "max"
        port_range_max = port_range["max"].to_i
        if port_range_max > 65535 || port_range_max < 1024
          raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component, "Max port range must be between 1024 and 65535")
        end
        if port_range_max < current_min
          raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component, "Maximum port range must be an equal or greater value than the current minimum port range value of #{current_min}");
        end
        logger.info("Setting harbor_node/port_range/max to #{port_range_max}")
        Kato::Config.set("harbor_node", "port_range/max", port_range_max)
      end
    end

    def _update_generic__positive_integer(component_id, key_path, value)
      value = value.to_i rescue nil
      if value.nil? or value <= 0
        raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component_id, "#{key_path} must be a (positive) number")
      end
      logger.info("Setting #{component_id} #{key_path} to #{value}")
      Kato::Config.set(component_id, key_path, value)
    end

    def _update__apptail__max_record_size(component_id, key, max_record_size)
      _update_generic__positive_integer(component_id, key, max_record_size)
    end
  
    def _update__systail__max_record_size(component_id, key, max_record_size)
      _update_generic__positive_integer(component_id, key, max_record_size)
    end
  
    def _update__cloud_controller_ng__app_uris(component, key, app_uris)
      if app_uris.key? "reserved_list"
        reserved_list = app_uris["reserved_list"]
        _assert_array_of_strings component, reserved_list, "reserved_list", 1
        logger.info("Setting CC app_uris/reserved_list to #{reserved_list}")
        Kato::Config.set("cloud_controller_ng", "app_uris/reserved_list", reserved_list)
      end
    end
  
    def _update__cloud_controller_ng__allowed_repos(component, key, allowed_repos)
      _assert_array_of_strings component, allowed_repos, "allowed_repos"
      logger.info("Setting CC allowed_repos to #{allowed_repos}")
      Kato::Config.set("cloud_controller_ng", "allowed_repos", allowed_repos)
    end
  
    def _update__cloud_controller_ng__app_store(component, key, app_store)
      min_length = 1
      stores = (app_store["stores"] || []).dup
      stores.delete_if {|store| !store.has_key?("url")}
      stores.each do |store|
        store.delete_if{|key, value| key != "url" && key != "enabled"}
        unless store["url"].kind_of?(String) && store["url"].size >= min_length
          raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component, "url must be a string of size at least #{min_length}")
        end
      end
      logger.info("Setting app_store to #{stores.inspect}")
      Kato::Config.set("cloud_controller_ng", "app_store/stores", stores)
    end

    def _update__cloud_controller_ng__staging(component_id, staging_key, staging_hash)
      if staging_hash.key? "max_staging_runtime"
        max_staging_runtime = staging_hash["max_staging_runtime"].to_i
        if max_staging_runtime <= 0
          raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component, "max_staging_runtime must be a (positive) number")
        end
        logger.info("Setting #{component_id} #{staging_key}/max_staging_runtime to #{max_staging_runtime}")
        Kato::Config.set(component_id, "#{staging_key}/max_staging_runtime", max_staging_runtime)
      end
    end

    def _update__dea_ng__staging(component_id, staging_key, staging_hash)
      if staging_hash.key? "max_staging_duration"
        max_staging_duration = staging_hash["max_staging_duration"].to_i
        if max_staging_duration <= 0
          raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component, "max_staging_duration must be a (positive) number")
        end
        logger.info("Setting #{component_id} #{staging_key}/max_staging_duration to #{max_staging_duration}")
        Kato::Config.set(component_id, "#{staging_key}/max_staging_duration", max_staging_duration)
      end
    end

    def _update__harbor_gateway__plan_management(component_id, key, plan_management)
      update_plan_management(component_id, key, plan_management)
    end

    def _update__mysql_gateway__plan_management(component_id, key, plan_management)
      update_plan_management(component_id, key, plan_management)
    end

    def _update__postgresql_gateway__plan_management(component_id, key, plan_management)
      update_plan_management(component_id, key, plan_management)
    end

    def _update__rabbit_gateway__plan_management(component_id, key, plan_management)
      update_plan_management(component_id, key, plan_management)
    end

    def _update__rabbit3_gateway__plan_management(component_id, key, plan_management)
      update_plan_management(component_id, key, plan_management)
    end

    def _update__redis_gateway__plan_management(component_id, key, plan_management)
      update_plan_management(component_id, key, plan_management)
    end

    def _update__mongodb_gateway__plan_management(component_id, key, plan_management)
      update_plan_management(component_id, key, plan_management)
    end

    def _update__filesystem_gateway__plan_management(component_id, key, plan_management)
      update_plan_management(component_id, key, plan_management)
    end

    def _update__memcached_gateway__plan_management(component_id, key, plan_management)
      update_plan_management(component_id, key, plan_management)
    end

    def update_plan_management(component_id, key, plan_management)
      plan_management["plans"].each do |plan_id, plan|
        if [true, false].include? plan["allow_over_provisioning"]
          Kato::Config.set(
            component_id,
            "#{key}/plans/#{plan_id}/allow_over_provisioning",
            plan["allow_over_provisioning"]
          )
        end
      end
    end

    def _assert_array_of_strings(component, arr, name, min_length=nil)
      if arr.is_a? Array
        arr.each do |item|
          unless (item.is_a? String and (min_length.nil? or item.size >= min_length))
            raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component, "#{name} array must contain strings of size at least #{min_length}")
          end
        end
      else
        raise ::VCAP::Errors::StackatoConfigUnsupportedUpdate.new(component, "`#{name}' should be of array type")
      end
    end

    # should only have config_permissions for existing config
    def self.find_redundant_permissions
      def self.test_config_exists(component_id, path, value)
        if value.is_a? Hash
          value.each_pair do |k, v|
            test_config_exists(component_id, File.join(path, k), v)
          end
        else
          if Kato::Config.get(component_id, path).nil?
            $stderr.puts "WARNING: Stackato redundant config permission: #{component_id} #{path}"
          end
        end
      end
      PERMISSIONS.each_pair do |component_id, value|
        test_config_exists(component_id, "/", value)
      end
    end

    # should only have config update methods for permission RW
    def self.find_redundant_updaters
      VCAP::CloudController::StackatoConfig.new("all").private_methods.sort.each do |method_sym|
        method_name = method_sym.to_s
        next unless method_name.start_with? "_update__"
        next if method_name == "_update__logging"
        match = (/^_update__(.*)__(.*)$/.match(method_name) || /^_update__(.*)$/.match(method_name))
        component_id = match[1]
        key = match[2]
        if Kato::Config.get(component_id, key).nil?
          $stderr.puts "WARN Stackato redundant config updater: #{method_name}"
        end
      end
    end

    # On startup, log as WARN any redundancy in configuration methods or permissions
    find_redundant_permissions
    find_redundant_updaters

  end
end
