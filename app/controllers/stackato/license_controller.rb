
require "kato/config"

module VCAP::CloudController
  class LicenseController < RestController::Base
    allow_unauthenticated_access

    def license
      license_value = Kato::Config.get("cluster", "license")
      if license_value
        Yajl::Encoder.encode(license_value)
      else
        Errors::ConsoleNotLicensed.new
      end
    end

    get "/stackato/license", :license

  end
end
