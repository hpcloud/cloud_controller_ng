
require "kato/config"
require "cloud_controller/stackato/config"

module VCAP::CloudController
  class StackatoConfigController < RestController::Base
    allow_unauthenticated_access

    # Return whitelisted fields in any vcap configuration
    # Only cloud_controller.yml supported for now.
    def get_config

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
      component_name = params["name"]
      new_config = Yajl::Parser.parse(body)
      logger.info("Newconfig: #{new_config}")
      StackatoConfig.new(component_name).save(new_config)
      [204, {}, nil]
    end

    get "/stackato/config", :get_config
    put "/stackato/config", :put_config

  end
end
