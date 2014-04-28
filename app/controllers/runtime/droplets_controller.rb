module VCAP::CloudController
  class DropletsController < RestController::ModelController
    define_attributes do
      to_one    :app
      attribute :guid, String
      attribute :package_hash, String
    end

    query_parameters :app_guid, :package_hash

    def delete(guid)
      do_delete(find_guid_and_validate_access(:delete, guid))
    end

    define_messages
    define_routes
  end
end
