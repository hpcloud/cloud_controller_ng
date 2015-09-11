
module VCAP::CloudController
  class StackatoAppLogsClient

    def self.fetch_app_loglines(app, num=25, raw=false, as_is=false)
      raise Errors::ApiError.new_from_details("StackatoClientUpgradeNeeded",
        "Viewing application logs requires version 4 of the Stackato client")
      end
    end

  end
end
