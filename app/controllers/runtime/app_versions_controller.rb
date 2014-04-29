module VCAP::CloudController
  class AppVersionsController < RestController::ModelController
    define_attributes do
      to_one    :app
      to_one    :droplet
      attribute :version_guid, String
      attribute :droplet_hash, String
      attribute :version_count, Integer
      attribute :description, String
    end

    query_parameters :app_guid, :version_guid, :description, :instances, :version_count, :droplet_hash

    def delete(guid)
      do_delete(find_guid_and_validate_access(:delete, guid))
    end

    define_messages
    define_routes
  end
end
