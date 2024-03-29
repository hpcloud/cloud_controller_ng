module VCAP::CloudController
  class EventsController < RestController::ModelController
    query_parameters :timestamp, :type, :actee

    def self.default_order_by
      :timestamp
    end

    def delete(guid)
      do_delete(find_guid_and_validate_access(:delete, guid))
    end

    define_messages
    define_routes
  end
end
