
require "kato/config"

module VCAP::CloudController
  class StackatoLicenseController < RestController::Base
    allow_unauthenticated_access

    def get_license
      license_value = Kato::Config.get("cluster", "license")
      if license_value
        Yajl::Encoder.encode(license_value)
      else
        raise Errors::StackatoNotLicensed.new
      end
    end

    get "/stackato/license", :get_license

  end
end
