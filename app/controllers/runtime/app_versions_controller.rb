module VCAP::CloudController
  class AppVersionsController < RestController::ModelController
    define_attributes do
      to_one    :app
      attribute :version_guid, String
    end

    query_parameters :app_guid, :version_guid

    def delete(guid)
      do_delete(find_guid_and_validate_access(:delete, guid))
    end

    define_messages
    define_routes
  end
end
