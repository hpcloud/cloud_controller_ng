module VCAP::CloudController
  rest_controller :Session do
    permissions_required do
      full Permissions::CFAdmin
      read Permissions::OrgManager
      read Permissions::SpaceManager
      full Permissions::SpaceDeveloper
      read Permissions::SpaceAuditor
    end

    define_attributes do
      to_one :app
      attribute :public_key, String
    end
  end
end
