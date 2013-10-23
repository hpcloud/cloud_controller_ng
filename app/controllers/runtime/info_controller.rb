require 'kato/config'

module VCAP::CloudController
  class InfoController < RestController::Base
    allow_unauthenticated_access

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
        :stackato => {
            :license_accepted => !license.blank?
        }
      }

      if user
        info[:user] = user.guid
        info[:stackato][:cc_nginx] = cc_nginx
      end

      Yajl::Encoder.encode(info)
    end

    get "/v2/info", :read
  end
end
