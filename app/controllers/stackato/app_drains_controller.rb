
require "kato/config"
require "cloud_controller/stackato/app_drains"

module VCAP::CloudController
  rest_controller :StackatoAppDrains do
    path_base "apps"
    model_class_name :App

    def get_app_drains(app_guid)
      app = find_guid_and_validate_access(:read, app_guid)
      drains = StackatoAppDrains.list(app)
      Yajl::Encoder.encode(drains)
    end

    def create_app_drain(app_guid)
      check_maintenance_mode
      app = find_guid_and_validate_access(:update, app_guid)
      max_drains_per_app = @config[:max_drains_per_app]
      if StackatoAppDrains.app_drains_count(app) >= max_drains_per_app
        raise Errors::StackatoAppDrainLimitReached.new(max_drains_per_app)
      end

      # TODO:Stackato: Implement user specific account capacity for drains.
      #limit = @app.owner.account_capacity[:drains]
      #usage = AppDrains.list(@app.id).length
      #if usage >= limit
      #  raise CloudError.new(CloudError::ACCOUNT_APP_TOO_MANY_DRAINS, usage, limit)
      #end

      body_params = Yajl::Parser.parse(body)

      drain_name = body_params["drain"]
      StackatoAppDrains.validate_name drain_name
      uri = body_params["uri"]
      StackatoAppDrains.validate_uri uri
      json = body_params["json"]

      StackatoAppDrains.create app, drain_name, uri, json

      [204, {}, nil]
    end

    def delete_app_drain(app_guid, drain_name)
      check_maintenance_mode
      app = find_guid_and_validate_access(:update, app_guid)
      StackatoAppDrains.validate_name drain_name
      StackatoAppDrains.delete app, drain_name
      [204, {}, nil]
    end

    get "#{path_guid}/stackato_drains", :get_app_drains
    post "#{path_guid}/stackato_drains", :create_app_drain
    delete "#{path_guid}/stackato_drains/:drain_name", :delete_app_drain

  end
end
