
module VCAP::CloudController
  rest_controller :StackatoAppLogs do
    path_base "apps"
    model_class_name :App

    def get_app_logs(guid)
      raise Errors::ApiError.new_from_details("StackatoClientUpgradeNeeded",
                          "Viewing application logs requires version 4 of the stackato client")
    end

    get "#{path_guid}/stackato_logs", :get_app_logs
  end
end
