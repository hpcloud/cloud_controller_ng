require 'kato/config'
require 'kato/cluster/license'
require 'cloud_controller/stackato/cluster_config'
require 'cloud_controller/stackato/license_helper'
require 'cloud_controller/stackato/vendor_config'

module VCAP::CloudController
  class InfoController < RestController::BaseController
    allow_unauthenticated_access

    get "/v2/info", :read
    def read
      license = Kato::Config.get("cluster", "license")
      info = {
        name: @config[:info][:name],
        build: @config[:info][:build],
        support: @config[:info][:support_address],
        version: @config[:info][:version],
        description: @config[:info][:description],
        authorization_endpoint: @config[:login] ? @config[:login][:url] : @config[:uaa][:url],
        token_endpoint: config[:uaa][:url],
        api_version: VCAP::CloudController::Constants::API_VERSION,
        vendor_version: StackatoVendorConfig.vendor_version,
        stackato: {
            license_accepted: StackatoLicenseHelper.get_license_accepted(license),
            zero_downtime: true,
            UUID: STACKATO_UUID
        }
      }

      if @config[:loggregator] && @config[:loggregator][:url]
        info[:logging_endpoint] = @config[:loggregator][:url]
      end

      if @config[:info][:custom]
        info[:custom] = @config[:info][:custom]
      end
      if user
        info[:user] = user.guid
        info[:stackato][:cc_nginx] = @config.fetch(:nginx, {}).fetch(:use_nginx, false)
        info[:maintenance_mode] = Config.config[:maintenance_mode]
        if user.admin?
          StackatoClusterConfig.update_license_info(info, license)
        end
      end

      MultiJson.dump(info)
    end
  end
end
