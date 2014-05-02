module VCAP::CloudController
  class AppsController < RestController::ModelController
    define_attributes do
      attribute  :name,                String
      attribute  :production,          Message::Boolean,    :default => false

      to_one     :space
      to_one     :stack,               :optional_in => :create

      attribute  :environment_json,    Hash,       :default => {}
      attribute  :system_env_json,     Hash,       :default => {}
      attribute  :memory,              Integer,    :default => nil
      attribute  :instances,           Integer,    :default => 1
      attribute  :disk_quota,          Integer,    :default => 1024

      attribute  :state,               String,     :default => "STOPPED"
      attribute  :command,             String,     :default => nil
      attribute  :console,             Message::Boolean, :default => false
      attribute  :debug,               String,     :default => nil
      attribute  :health_check_timeout, Integer,   :default => nil

      attribute  :distribution_zone,   String,     :default => "default"
      attribute  :description,         String,     :default => ""
      attribute  :sso_enabled,         Message::Boolean, :default => false

      # Fields for autoscaling
      attribute  :min_cpu_threshold,   Integer,    :default => nil
      attribute  :max_cpu_threshold,   Integer,    :default => nil
      attribute  :min_instances,       Integer,    :default => nil
      attribute  :max_instances,       Integer,    :default => nil
      attribute  :autoscale_enabled,   Message::Boolean,    :default => false

      attribute  :buildpack,           String, :default => nil
      attribute  :detected_buildpack,  String, :exclude_in => [:create, :update]

      to_many    :service_bindings,    :exclude_in => :create
      to_many    :routes
      to_many    :app_versions, :exclude_in => :create

      to_many    :events
    end

    query_parameters :name, :space_guid, :organization_guid, :restart_required, :state, :package_state, :sso_enabled

    def self.default_order_by
      :name
    end

    def self.translate_validation_exception(e, attributes)
      space_and_name_errors = e.errors.on([:space_id, :name])
      memory_quota_errors = e.errors.on(:memory)
      instance_number_errors = e.errors.on(:instances)

      if space_and_name_errors && space_and_name_errors.include?(:unique)
        Errors::AppNameTaken.new(attributes["name"])
      elsif memory_quota_errors
        if memory_quota_errors.include?(:quota_exceeded)
          Errors::AppMemoryQuotaExceeded.new
        elsif memory_quota_errors.include?(:zero_or_less)
          Errors::AppMemoryInvalid.new
        end
      elsif instance_number_errors
        Errors::AppInvalid.new("Number of instances less than 0")
      else
        Errors::AppInvalid.new(e.errors.full_messages)
      end
    end

    def inject_dependencies(dependencies)
      @app_event_repository = dependencies.fetch(:app_event_repository)
      @health_manager_client = dependencies.fetch(:health_manager_client)
    end

    def delete(guid)

      check_maintenance_mode
      app = find_guid_and_validate_access(:delete, guid)

      if !recursive? && app.service_bindings.present?
        raise VCAP::Errors::AssociationNotEmpty.new("service_bindings", app.class.table_name)
      end

      name = app[:name]
      event = {
        :user => SecurityContext.current_user,
        :app => app,
        :event => 'APP_DELETED',
        :instance_index => -1,
        :message => "Deleted app '#{name}'"
      }
      logger.info("TIMELINE #{event.to_json}")
      @app_event_repository.record_app_delete_request(app, SecurityContext.current_user, recursive?)
      app.destroy

      [ HTTP::NO_CONTENT, nil ]
    end
    
    def adjust_instances(app_guid, payload)
      instances = payload[:instances]
      if instances && instances.kind_of?(Array) && instances.size == 2
        before_count = instances[0]
        payload[:instances] = after_count = instances[1]
      end
      
      @request_attrs = payload
      
      # No need to validate access since this came from the health_manager responder.
      # There shouldn't be a route to this method.
      app = model.find(guid: app_guid)
      if payload[:instances]
        # Look at the direction we're supposed to go in, and bail out if we're
        # already there
        if before_count < after_count
          if app.instances >= after_count
            return
          end
        elsif before_count > after_count
          if app.instances <= after_count
            return
          end
        elsif app.instances == after_count
          return
        end
      end
      before_update(app)

      model.db.transaction(savepoint: true) do
        app.lock!
        app.update_from_hash(payload)
        app.save
      end
      if app.dea_update_pending?
        DeaClient.update_uris(app)
      end
    end

    private

    def after_create(app)
      record_app_create_value = @app_event_repository.record_app_create(app, SecurityContext.current_user, request_attrs)
      record_app_create_value if request_attrs
      update_health_manager_for_autoscaling(app)

      event = {
        :user => SecurityContext.current_user,
        :app => app,
        :event => 'APP_CREATED',
        :instance_index => -1,
        :message => "Created app '#{app.name}'"
      }
      logger.info("TIMELINE #{event.to_json}")
    end

    def after_update(app)
      stager_response = app.last_stager_response
      if stager_response && stager_response.streaming_log_url
        set_header("X-App-Staging-Log", stager_response.streaming_log_url)
      end

      if app.dea_update_pending?
        DeaClient.update_uris(app)
      end

      @app_event_repository.record_app_update(app, SecurityContext.current_user, request_attrs)
      update_health_manager_for_autoscaling(app)

      event = {
        :user => SecurityContext.current_user,
        :app => app,
        :changes => app.auditable_changes,
        :event => 'APP_UPDATED',
        :instance_index => -1,
        :message => "Updated app '#{app.name}' -- #{App.audit_hash(request_attrs)}"
      }
      logger.info("TIMELINE #{event.to_json}")
    end
    
    def update_health_manager_for_autoscaling(app)
      changes = {}
      [:min_cpu_threshold, :max_cpu_threshold, :min_instances, :max_instances,
       :autoscale_enabled].each { |k| changes[k] = app.send(k) }
      changes[:appid] = app.guid
      changes[:react] = false
      @health_manager_client.update_autoscaling_fields(changes)
    end

    define_messages
    define_routes
  end
end
