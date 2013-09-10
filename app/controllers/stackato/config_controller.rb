
require "cloud_controller/stackato/config"

module VCAP::CloudController
  class StackatoConfigController < RestController::Base

    # Return whitelisted fields in any vcap configuration
    # Only cloud_controller.yml supported for now.
    def get_config
      raise Errors::NotAuthorized unless roles.admin?
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
      raise Errors::NotAuthorized unless roles.admin?
      component_name = params["name"]
      new_config = Yajl::Parser.parse(body)
      logger.info("Newconfig: #{new_config}")
      StackatoConfig.new(component_name).save(new_config)
      [204, {}, nil]
    end

    get "/v2/stackato/config", :get_config
    put "/v2/stackato/config", :put_config

  end
end
