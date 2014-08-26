require 'yajl'

require "kato/config"
require 'kato/cluster/util'

module VCAP::CloudController
  class StackatoLicenseController < RestController::BaseController
    allow_unauthenticated_access

    def set_license
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?

      data = Yajl::Parser.parse(body)

      if not data.is_a? Hash or not data['license'].is_a? String
        raise Errors::ApiError.new_from_details("StackatoLicenseInvalid")
      end

      begin
        Kato::Config.set('cluster', 'license', data['license'], force: true)
      rescue KatoBadParamsException
        raise Errors::ApiError.new_from_details("StackatoLicenseInvalid")
      end
    end

    put "/v2/stackato/license", :set_license

    def parse_license
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?

      data = Yajl::Parser.parse(body)

      if not data.is_a? Hash or not data['license'].is_a? String
        raise Errors::ApiError.new_from_details("StackatoLicenseInvalid")
      end

      begin
        Yajl::Encoder.encode(Kato::Cluster::Util.parse_license(data['license']))
      rescue KatoBadParamsException
        raise Errors::ApiError.new_from_details("StackatoLicenseInvalid")
      end
    end

    post "/v2/stackato/license/parse", :parse_license
  end
end
