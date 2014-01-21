require 'kato/config'
require 'cloud_controller/stackato/vendor_config'

module VCAP::CloudController
  class InfoController < RestController::Base
    allow_unauthenticated_access

    get "/v2/info", :read
    def read
      license = Kato::Config.get("cluster", "license")
      cc_nginx = Kato::Config.get("cloud_controller_ng", "nginx").fetch("use_nginx", false)
      info = {
        :name        => @config[:info][:name],
        :build       => @config[:info][:build],
        :support     => @config[:info][:support_address],
        :version     => @config[:info][:version],
        :description => @config[:info][:description],
        :authorization_endpoint => @config[:login] ? @config[:login][:url] : @config[:uaa][:url],
        :api_version => @config[:info][:api_version],
        :vendor_version => StackatoVendorConfig.vendor_version,
        :stackato => {
            :license_accepted => !license.blank?,
            :UUID => STACKATO_UUID
        }
      }

      if user
        info[:user] = user.guid
        info[:stackato][:cc_nginx] = cc_nginx
      end

      Yajl::Encoder.encode(info)
    end
  end
end
