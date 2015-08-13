
module VCAP::CloudController
  rest_controller :StackatoAppDrains do
    path_base "apps"
    model_class_name :App
    
    # v4 drains are instances of user-provided services, so there's no need
    # for this endpoint.

    def get_app_drains(app_guid)
      raise Errors::ApiError.new_from_details("StackatoClientUpgradeNeeded",
                          "Manipulating application drains requires version 4 of the Stackato client")
    end

    def create_app_drain(app_guid)
      raise Errors::ApiError.new_from_details("StackatoClientUpgradeNeeded",
                          "Creating app drains requires version 4 of the stackato client")
    end

    def delete_app_drain(app_guid, drain_name)
      raise Errors::ApiError.new_from_details("StackatoClientUpgradeNeeded",
                          "Deleting app drains requires version 4 of the stackato client")
    end

    get "#{path_guid}/stackato_drains", :get_app_drains
    post "#{path_guid}/stackato_drains", :create_app_drain
    delete "#{path_guid}/stackato_drains/:drain_name", :delete_app_drain

  end
end
