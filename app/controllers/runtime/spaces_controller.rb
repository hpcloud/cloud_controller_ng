module VCAP::CloudController
  rest_controller :Spaces do
    define_attributes do
      attribute  :name,            String
      to_one     :organization
      to_many    :developers
      to_many    :managers
      to_many    :auditors
      to_many    :apps
      to_many    :domains
      to_many    :service_instances
      to_many    :app_events
      to_many    :events
    end

    query_parameters :name, :organization_guid, :developer_guid, :app_guid

    def self.translate_validation_exception(e, attributes)
      name_errors = e.errors.on([:organization_id, :name])
      if name_errors && name_errors.include?(:unique)
        Errors::SpaceNameTaken.new(attributes["name"])
      elsif name_errors && name_errors.include?(:max_length)
        Errors::StackatoParameterLengthInvalid.new(64, attributes["name"])
      else
        Errors::SpaceInvalid.new(e.errors.full_messages)
      end
    end

    get "/v2/spaces/:guid/services", :enumerate_services

    def enumerate_services(guid)
      space = find_guid_and_validate_access(:read, guid)

      services = Query.filtered_dataset_from_query_params(
        Service,
        Service.organization_visible(space.organization),
        ServicesController.query_parameters,
        @opts
      )

      RestController::Paginator.render_json(
          ServicesController,
          services,
          "/v2/spaces/#{guid}/services",
          @opts
      )
    end

    get "/v2/spaces/:guid/service_instances", :enumerate_service_instances

    def enumerate_service_instances(guid)
      space = find_guid_and_validate_access(:read, guid)

      if params['return_user_provided_service_instances'] == 'true'
        model_class = ServiceInstance
        relation_name = :service_instances
      else
        model_class = ManagedServiceInstance
        relation_name = :managed_service_instances
      end

      service_instances = Query.filtered_dataset_from_query_params(model_class,
        space.user_visible_relationship_dataset(relation_name, SecurityContext.current_user, SecurityContext.admin?),
        ServiceInstancesController.query_parameters,
        @opts)
      service_instances.filter(space: space)

      RestController::Paginator.render_json(
        ServiceInstancesController,
        service_instances,
        "/v2/spaces/#{guid}/service_instances",
        @opts
      )
    end

  end
end
