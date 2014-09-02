require 'uri'
require 'yaml'
require 'kato/config'
require 'cloud_controller/stackato/config'

module VCAP::CloudController
  class StackatoConfigController < RestController::BaseController

    CONFIG_BLACKLIST = YAML.load_file(File.join(File.dirname(__FILE__), "..", "..", "..", "config", "stackato", "config_blacklist.yml"))
    CONFIG_KEYS_BLACKLIST = CONFIG_BLACKLIST["key_blacklist"]
    CONFIG_COMPONENTS_BLACKLIST = CONFIG_BLACKLIST["component_blacklist"]

    # Recurses through a hash (and nested hashes) and rejects keys that exist in the keys array
    def deep_reject(hash, keys)
      hash.is_a?(Hash) ? hash.inject({}) do |m, (k, v)|
        m[k] = deep_reject(v, keys) unless keys.include?(k) # TODO: We could set the key to a junk value, to expose its existence?
        m
      end : hash
    end

    # Gets the list of Stackato components that can be configured via the api
    def get_component_list
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      components = Kato::Config.component_ids.select { |component| !CONFIG_COMPONENTS_BLACKLIST.include?(component)}
      components = components.map { |component| {:name => component, :url => "/v2/stackato/config/components/#{URI.escape(component)}" }}
      Yajl::Encoder.encode(components)
    end
    get "/v2/stackato/config/components", :get_component_list

    # Gets the config for a specific component
    def get_component_config(component_name)
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      component_name = component_name.gsub(/\-/, '_')
      raise Errors::ApiError.new_from_details("StackatoComponentNotFound", component_name) unless !CONFIG_COMPONENTS_BLACKLIST.include?(component_name)
      component_config = Kato::Config.get(component_name)
      raise Errors::ApiError.new_from_details("StackatoNoConfigForComponent", component_name) unless component_config
      component_config = deep_reject(component_config, CONFIG_KEYS_BLACKLIST)
      Yajl::Encoder.encode(component_config)
    end
    get "/v2/stackato/config/components/:component_name", :get_component_config

    # Updates the config for a specific component
    def update_component_config(component_name)
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      component_name = component_name.gsub(/\-/, '_')
      raise Errors::ApiError.new_from_details("StackatoComponentNotFound", component_name) unless !CONFIG_COMPONENTS_BLACKLIST.include?(component_name)
      component_config = Yajl::Parser.parse(body)
      raise Errors::ApiError.new_from_details("StackatoConfigUnsupportedUpdate", component_name, "No config provided.") unless component_config.is_a? Hash and component_config.size > 0
      component_config = deep_reject(component_config, CONFIG_KEYS_BLACKLIST)
      StackatoConfig.new(component_name).save(component_config)
      [204, {}, nil]
    end
    put "/v2/stackato/config/components/:component_name", :update_component_config

    ## TODO Api call to update specific config value

    # Return whitelisted fields in any vcap configuration
    # Only cloud_controller.yml supported for now.
    def get_config
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      component_name = params["name"]
      unless component_name
        raise Errors::ApiError.new_from_details("StackatoNoComponentNameGiven")
      end

      # Ensure we have underscore component names
      component_name = component_name.gsub(/\-/, '_')

      config = StackatoConfig.new(component_name).get_viewable
      unless config
        raise Errors::ApiError.new_from_details("StackatoNoConfigForComponent", component_name)
      end

      logger.info("Returning whitelist properties for #{component_name}")
      Yajl::Encoder.encode(config)
    end

    def put_config
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      component_name = params["name"]
      new_config = Yajl::Parser.parse(body)
      unless new_config.is_a? Hash and new_config.size > 0
        raise Errors::ApiError.new_from_details("StackatoConfigUnsupportedUpdate", component_name, "No config given.")
      end
      logger.info("Newconfig: #{new_config}")
      StackatoConfig.new(component_name).save(new_config)
      [204, {}, nil]
    end

    get "/v2/stackato/config", :get_config
    put "/v2/stackato/config", :put_config

  end
end
