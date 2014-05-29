module VCAP::CloudController
  class QuotaDefinitionsController < RestController::ModelController
    define_attributes do
      attribute  :name,                       String
      attribute  :non_basic_services_allowed, Message::Boolean
      attribute  :total_services,             Integer
      attribute  :total_routes,               Integer
      attribute  :total_droplets,             Integer, :default => 0
      attribute  :memory_limit,               Integer
      attribute  :allow_sudo,                 Message::Boolean, :default => false
    end

    query_parameters :name, :allow_sudo

    def self.default_order_by
      :name
    end

    def self.translate_validation_exception(e, attributes)
      name_errors = e.errors.on(:name)
      if name_errors && name_errors.include?(:unique)
        Errors::ApiError.new_from_details("QuotaDefinitionNameTaken", attributes["name"])
      else
        Errors::ApiError.new_from_details("QuotaDefinitionInvalid", e.errors.full_messages)
      end
    end

    def delete(guid)
      do_delete(find_guid_and_validate_access(:delete, guid))
    end

    define_messages
    define_routes
  end
end
