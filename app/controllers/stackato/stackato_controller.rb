require 'kato/config'

module VCAP::CloudController
  class StackatoController < RestController::Base
    disable_default_routes
    path_base "stackato"
    permissions_required do
      read Permissions::CFAdmin
      read Permissions::OrgManager
      read Permissions::SpaceManager
      read Permissions::SpaceDeveloper
      read Permissions::SpaceAuditor
    end

    def license()
        license_value = Kato::Config.get("cluster", "license")
        if license_value
          Yajl::Encoder.encode(info)
        else
          raise CloudError.new(CloudError::CONSOLE_UNLICENSED)
        end
    end

    get "license", :license
  end
end