require 'yajl'

require "kato/config"
require 'kato/cluster/util'

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

    get "/v2/stackato/license", :get_license

    def set_license
      raise Errors::NotAuthorized unless roles.admin?

      data = Yajl::Parser.parse(body)

      if not data.is_a? Hash or not data['license'].is_a? String
        raise Errors::StackatoLicenseInvalid.new
      end

      begin
        Kato::Config.set('cluster', 'license', data['license'], force: true)
      rescue KatoBadParamsException
        raise Errors::StackatoLicenseInvalid.new
      end
    end

    put "/v2/stackato/license", :set_license

    def parse_license
      raise Errors::NotAuthorized unless roles.admin?

      data = Yajl::Parser.parse(body)

      if not data.is_a? Hash or not data['license'].is_a? String
        raise Errors::StackatoLicenseInvalid.new
      end

      begin
        Yajl::Encoder.encode(Kato::Cluster::Util.parse_license(data['license']))
      rescue KatoBadParamsException
        raise Errors::StackatoLicenseInvalid.new
      end
    end

    post "/v2/stackato/license/parse", :parse_license
  end
end
