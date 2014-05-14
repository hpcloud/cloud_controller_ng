require 'kato/config'
require 'kato/cluster/license'
require 'cloud_controller/stackato/cluster_config'
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
        :api_version => VCAP::CloudController::Constants::API_VERSION,
        :vendor_version => StackatoVendorConfig.vendor_version,
        :stackato => {
            :license_accepted => !license.blank?,
            :UUID => STACKATO_UUID
        }
      }

      if user
        info[:user] = user.guid
        info[:stackato][:cc_nginx] = cc_nginx
        info[:maintenance_mode] = Config.config[:maintenance_mode]
      end
      StackatoClusterConfig.update_license_info(info, license)

      Yajl::Encoder.encode(info)
    end
  end
end
