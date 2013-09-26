
require "cloud_controller/stackato/config"

module VCAP::CloudController
  class StackatoConfigController < RestController::Base
    # TODO:Stackato: remove this line
    allow_unauthenticated_access

    # Return whitelisted fields in any vcap configuration
    # Only cloud_controller.yml supported for now.
    def get_config
      # TODO:Stackato: re-enable this line
      #raise Errors::NotAuthorized unless roles.admin?
      component_name = params["name"]
      unless component_name
        raise Errors::StackatoNoComponentNameGiven.new
      end

      # Ensure we have underscore component names
      component_name = component_name.gsub(/\-/, '_')

      config = StackatoConfig.new(component_name).get_viewable
      unless config
        raise Errors::StackatoNoConfigForComponent.new(component_name)
      end

      logger.info("Returning whitelist properties for #{component_name}")
      Yajl::Encoder.encode(config)
    end

    def put_config
      # TODO:Stackato: re-enable this line
      #raise Errors::NotAuthorized unless roles.admin?
      component_name = params["name"]
      unless new_config.is_a? Hash and new_config.size > 0
        raise Errors::StackatoConfigUnsupportedUpdate.new(component_name, "No config given.")
      end
      new_config = Yajl::Parser.parse(body)
      logger.info("Newconfig: #{new_config}")
      StackatoConfig.new(component_name).save(new_config)
      [204, {}, nil]
    end

    get "/v2/stackato/config", :get_config
    put "/v2/stackato/config", :put_config

  end
end
