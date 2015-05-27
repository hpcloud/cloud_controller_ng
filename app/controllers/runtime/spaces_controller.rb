require 'actions/space_delete'

module VCAP::CloudController
  class SpacesController < RestController::ModelController
    def self.dependencies
      [:space_event_repository]
    end

    define_attributes do
      attribute  :name,            String
      attribute  :is_default, Message::Boolean, default: false
      to_one     :organization
      to_many    :developers
      to_many    :managers
      to_many    :auditors
      to_many    :apps,                    exclude_in: [:create, :update], route_for: :get
      to_many    :routes,                  exclude_in: [:create, :update], route_for: :get
      to_many    :domains
      to_many    :service_instances,       route_for: :get
      to_many    :app_events,              link_only: true, exclude_in: [:create, :update], route_for: :get
      to_many    :events,                  link_only: true, exclude_in: [:create, :update], route_for: :get
      to_many    :security_groups
      to_one     :space_quota_definition,  optional_in: [:create], exclude_in: [:update]
    end

    query_parameters :name, :organization_guid, :developer_guid, :manager_guid, :app_guid

    deprecated_endpoint "#{path_guid}/domains"

    def self.translate_validation_exception(e, attributes)
      name_errors = e.errors.on([:organization_id, :name])
      if name_errors && name_errors.include?(:unique)
        Errors::ApiError.new_from_details('SpaceNameTaken', attributes['name'])
      elsif name_errors && name_errors.include?(:max_length)
        Errors::ApiError.new_from_details('StackatoParameterLengthInvalid', 64, attributes['name'])
      else
        Errors::ApiError.new_from_details('SpaceInvalid', e.errors.full_messages)
      end
    end

    def inject_dependencies(dependencies)
      super
      @space_event_repository = dependencies.fetch(:space_event_repository)
    end

    get '/v2/spaces/:guid/services', :enumerate_services
    def enumerate_services(guid)
      space = find_guid_and_validate_access(:read, guid)

      associated_controller, associated_model = ServicesController, Service

      filtered_dataset = Query.filtered_dataset_from_query_params(
        associated_model,
        associated_model.organization_visible(space.organization),
        associated_controller.query_parameters,
        @opts,
      )

      associated_path = "#{self.class.url_for_guid(guid)}/services"

      opts = @opts.merge(
        additional_visibility_filters: {
          service_plans: proc { |ds| ds.organization_visible(space.organization) },
        }
      )

      collection_renderer.render_json(
        associated_controller,
        filtered_dataset,
        associated_path,
        opts,
        {},
      )
    end

    get '/v2/spaces/:guid/service_instances', :enumerate_service_instances
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

      collection_renderer.render_json(
        ServiceInstancesController,
        service_instances,
        "/v2/spaces/#{guid}/service_instances",
        @opts,
        {}
      )
    end

    def delete(guid)
      space = find_guid_and_validate_access(:delete, guid)
      raise_if_has_associations!(space) if v2_api? && !recursive?

      if !space.app_models.empty? && !recursive?
        raise VCAP::Errors::ApiError.new_from_details('AssociationNotEmpty', 'app_model', Space.table_name)
      end

      if !space.service_instances.empty? && !recursive?
        raise VCAP::Errors::ApiError.new_from_details('AssociationNotEmpty', 'service_instances', Space.table_name)
      end

      @space_event_repository.record_space_delete_request(space, SecurityContext.current_user, SecurityContext.current_user_email, recursive?)

      delete_action = SpaceDelete.new(current_user.id, current_user_email)
      deletion_job = VCAP::CloudController::Jobs::DeleteActionJob.new(Space, guid, delete_action)
      enqueue_deletion_job(deletion_job)
    end

    private
    def after_create(space)
      @space_event_repository.record_space_create(space, SecurityContext.current_user, SecurityContext.current_user_email, request_attrs)
    end

    def after_update(space)
      @space_event_repository.record_space_update(space, SecurityContext.current_user, SecurityContext.current_user_email, request_attrs)
    end

    define_messages
    define_routes
  end
end
