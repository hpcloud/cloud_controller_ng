
module VCAP::CloudController
  rest_controller :StackatoAppLogs do
    path_base "apps"
    model_class_name :App

    def get_app_logs(guid)
      app = find_guid_and_validate_access(:read, guid)
      begin
        loglines = StackatoAppLogsClient.fetch_app_loglines(app, params["num"].to_i, params["raw"], params["as_is"])
      rescue Redis::CannotConnectError => e
        logger.error(e.message)
        raise Errors::ApiError.new_from_details("StackatoAppLogServerNotReachable")
      end
      if params["monolith"]
        # monolith return is used by the Web UI
        Yajl::Encoder.encode({:lines => loglines})
      else
        if params["as_is"]
          loglines.map {|line| line}.join("\n") + "\n"
        else
          loglines.map {|line| Yajl::Encoder.encode(line)}.join("\n") + "\n"
        end
      end
    end

    get "#{path_guid}/stackato_logs", :get_app_logs
  end
end
