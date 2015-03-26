require 'cloud_controller/app_observer'
require 'cloud_controller/database_uri_generator'
require 'cloud_controller/undo_app_changes'
require 'cloud_controller/errors/application_missing'
require 'cloud_controller/errors/invalid_route_relation'
require 'repositories/runtime/app_usage_event_repository'
require 'presenters/message_bus/service_binding_presenter'
require 'digest/sha1'

require_relative 'buildpack'
require_relative 'app_version'

module VCAP::CloudController
  # rubocop:disable ClassLength
  class App < Sequel::Model
    plugin :serialization
    plugin :after_initialize

    def after_initialize
      default_instances = db_schema[:instances][:default].to_i

      self.instances ||=  default_instances
      self.memory ||= VCAP::CloudController::Config.config[:default_app_memory]
    end

    APP_NAME_REGEX = /\A[[:print:]]+\Z/.freeze

    one_to_many :droplets
    one_to_many :app_versions
    one_to_many :service_bindings
    one_to_many :events, class: VCAP::CloudController::AppEvent
    one_to_one :app, class: 'VCAP::CloudController::AppModel', key: :guid, primary_key: :app_guid
    many_to_one :admin_buildpack, class: VCAP::CloudController::Buildpack
    many_to_one :space, after_set: :validate_space
    many_to_one :stack
    many_to_many :routes, before_add: :validate_route, after_add: :handle_add_route, after_remove: :handle_remove_route
    one_through_one :organization, join_table: :spaces, left_key: :id, left_primary_key: :space_id, right_key: :organization_id

    one_to_one :current_saved_droplet,
               class: '::VCAP::CloudController::Droplet',
               key: :droplet_hash,
               primary_key: :droplet_hash

    add_association_dependencies routes: :nullify, service_bindings: :destroy, events: :delete, droplets: :destroy

    export_attributes :guid, :name, :production, :space_guid, :stack_guid, :buildpack,
                      :detected_buildpack, :environment_json, :memory, :instances, :disk_quota,
                      :state, :version, :command, :console, :debug, :staging_task_id,
                      :package_state, :package_hash, :health_check_type, :health_check_timeout,
                      :system_env_json, :distribution_zone,
                      :description, :sso_enabled, :restart_required, :autoscale_enabled,
		      :min_cpu_threshold, :max_cpu_threshold, :min_instances, :max_instances,
		      :droplet_count, :staging_failed_reason, :diego,
		      :docker_image, :package_updated_at, :detected_start_command

    import_attributes :name, :production, :space_guid, :stack_guid, :buildpack,
                      :detected_buildpack, :environment_json, :memory, :instances, :disk_quota,
                      :state, :command, :console, :debug, :staging_task_id,
                      :service_binding_guids, :route_guids,
                      :health_check_timeout,
                      :health_check_type, :distribution_zone,
		      :description, :sso_enabled, :autoscale_enabled,
		      :min_cpu_threshold, :max_cpu_threshold, :min_instances, :max_instances,
		      :diego, :docker_image, :app_guid

    strip_attributes :name

    serialize_attributes :json, :metadata

    encrypt :environment_json, salt: :salt, column: :encrypted_environment_json

    APP_STATES = %w(STOPPED STARTED).map(&:freeze).freeze
    PACKAGE_STATES = %w(PENDING STAGED FAILED).map(&:freeze).freeze
    STAGING_FAILED_REASONS = %w(StagingError StagingTimeExpired NoAppDetectedError BuildpackCompileFailed
                                BuildpackReleaseFailed InsufficientResources NoCompatibleCell).map(&:freeze).freeze
    HEALTH_CHECK_TYPES = %w(port none).map(&:freeze).freeze

    # marked as true on changing the associated routes, and reset by
    # +Dea::Client.start+
    attr_accessor :routes_changed

    attr_accessor :version_description
    attr_accessor :version_updated
    attr_accessor :force_no_snapshot

    # Last staging response which will contain streaming log url
    attr_accessor :last_stager_response

    alias_method :diego?, :diego

    def copy_buildpack_errors
      bp = buildpack
      return if bp.valid?

      bp.errors.each do |err|
        errors.add(:buildpack, err)
      end
    end

    def validation_policies
      [
        AppEnvironmentPolicy.new(self),
        DiskQuotaPolicy.new(self, max_app_disk_in_mb),
        MetadataPolicy.new(self, metadata_deserialized),
        MinMemoryPolicy.new(self),
        MaxMemoryPolicy.new(self, space, :space_quota_exceeded),
        MaxMemoryPolicy.new(self, organization, :quota_exceeded),
        MaxInstanceMemoryPolicy.new(self, organization && organization.quota_definition, :instance_memory_limit_exceeded),
        MaxInstanceMemoryPolicy.new(self, space && space.space_quota_definition, :space_instance_memory_limit_exceeded),
        InstancesPolicy.new(self),
        HealthCheckPolicy.new(self, health_check_timeout),
        CustomBuildpackPolicy.new(self, custom_buildpacks_enabled?),
        DockerPolicy.new(self)
      ]
    end

    def validate
      validates_presence :name
      validates_app_name :name
      validates_presence :space
      validates_max_length 2048, :description, :allow_missing=>true
      validates_unique [:space_id, :name]
      validates_format APP_NAME_REGEX, :name

      copy_buildpack_errors

      validates_includes PACKAGE_STATES, :package_state, allow_missing: true
      validates_includes APP_STATES, :state, allow_missing: true, message: 'must be one of ' + APP_STATES.join(', ')
      validates_includes STAGING_FAILED_REASONS, :staging_failed_reason, allow_nil: true
      validates_includes HEALTH_CHECK_TYPES, :health_check_type, allow_missing: true, message: 'must be one of ' + HEALTH_CHECK_TYPES.join(', ')

      # REFACTOR: incorporate `validate_autoscaling_settings` into upstream's
      # `validation_policies` data structure
      validate_autoscaling_settings
      validation_policies.map(&:validate)
    end

    def before_create
      set_new_version
      super
    end

    def after_create
      super
      create_app_usage_event
    end

    def after_update
      super
      create_app_usage_event
    end

    def before_save
      if generate_start_event? && !package_hash
        raise VCAP::Errors::ApiError.new_from_details('AppPackageInvalid', 'bits have not been uploaded')
      end

      self.stack ||= Stack.default
      self.memory ||= Config.config[:default_app_memory]
      self.disk_quota ||= Config.config[:default_app_disk_in_mb]

      if Config.config[:instance_file_descriptor_limit]
        self.file_descriptors ||= Config.config[:instance_file_descriptor_limit]
      end

      set_new_version if version_needs_to_be_updated?
      
      update_requires_restart

      AppStopEvent.create_from_app(self) if generate_stop_event?
      AppStartEvent.create_from_app(self) if generate_start_event?

      adjust_route_sso_clients if sso_updated?
      self.min_instances = 1 if self.min_instances.nil? # Stackato bug 103723

      if diego.nil?
        self.diego = Config.config[:default_to_diego_backend]
      end

      super
    end

    def after_save
      snapshot_new_version if snapshot_necessary?
      #XXX Remove this comment
      # upstream commit cd1a8d9704cab3a3f6b9d1bef1c9d6291bdcce8d
      # on 2014-06-02 moved create_app_usage_event into
      # after_update and after_create, so they removed this entire
      # method.  We need it to set @changes (used in apps_controller.rb)
      #create_app_usage_event
      
      @changes = column_changes
      super
    end

    def auditable_changes
      @changes || {}
    end

    def snapshot_necessary?
      current_droplet && (column_changed?(:instances) || column_changed?(:memory) || column_changed?(:droplet_hash))
    end

    def snapshot_new_version
      if force_no_snapshot
        self.force_no_snapshot = false
        return
      end

      VCAP::CloudController::AppVersion.make_new_version(self)
    end

    def sso_updated?
      column_changed?(:sso_enabled)
    end

    def env_updated?
      column_changed?(:encrypted_environment_json)
    end

    def set_default_restart_required_state(initial=false)
        env = initial ? initial_value(:environment_json) : self.environment_json
        sso = initial ? initial_value(:sso_enabled) : self.sso_enabled
        env_sha1 = Digest::SHA1.hexdigest "#{env}"
        self.restart_required_state = {"sso_enabled" => sso, "env_sha1" => env_sha1}
    end

    def restart_required_state=(state)
      self.restart_required_state_json = Yajl::Encoder.encode(state || {})
    end

    def restart_required_state
     self.restart_required_state_json.to_s != '' ? Yajl::Parser.parse(self.restart_required_state_json) : set_default_restart_required_state(true) && restart_required_state
    end

    def update_requires_restart
      # If the app is being stopped or started we can reset the restart_required field
      if generate_stop_event? || generate_start_event?
        self.restart_required = false
        set_default_restart_required_state(false)
      # If the app is started (and was already started) then we may need to set restart_required if certain properties are being updated
      elsif started? && !being_started?
        needs_restart = false
        # A restart is required if env has changed, but only if it wasn't set back to it's original value since the last restart
        if env_updated?
          new_env_sha1 = Digest::SHA1.hexdigest "#{environment_json}"
          needs_restart = true unless self.restart_required_state["env_sha1"] == new_env_sha1
        end
        # A restart is required if sso_enabled has changed, but only if it wasn't set back to it's original value since the last restart 
        if sso_updated?
          needs_restart = true unless self.restart_required_state["sso_enabled"] == self.sso_enabled
        end
        self.restart_required = needs_restart
      end
    end

    def adjust_route_sso_clients
      routes.each do |route|
        # if we're turning SSO on, or any other app that maps this route
        # has SSO on, make sure oauth client is registered
        if sso_enabled || route.apps.reject{|a|a.guid == guid}.any?{|a|a.sso_enabled}
          route.register_oauth_client
        else
          route.delete_oauth_client
        end
      end
    end

    # Call VCAP::CloudController::Runners.run_with_diego? for the true answer
    def run_with_diego?
      !!(environment_json && environment_json['DIEGO_RUN_BETA'] == 'true')
    end

    def stage_with_diego?
      run_with_diego? || !!(environment_json && environment_json['DIEGO_STAGE_BETA'] == 'true')
    end

    def version_needs_to_be_updated?
      # change version if:
      #
      # * transitioning to STARTED
      # * memory is changed
      # * routes are changed
      #
      # this is to indicate that the running state of an application has changed,
      # and that the system should converge on this new version.
      (column_changed?(:state) || column_changed?(:memory) || column_changed?(:health_check_type) || (column_changed?(:droplet_hash) && column_change(:droplet_hash)[0])) && started?
    end

    def set_new_version
      self.version = SecureRandom.uuid
    end

    def update_detected_buildpack(detect_output, detected_buildpack_key)
      detected_admin_buildpack = Buildpack.find(key: detected_buildpack_key)
      if detected_admin_buildpack
        detected_buildpack_guid = detected_admin_buildpack.guid
        detected_buildpack_name = detected_admin_buildpack.name
      end

      update(
        detected_buildpack: detect_output,
        detected_buildpack_guid: detected_buildpack_guid,
        detected_buildpack_name: detected_buildpack_name || custom_buildpack_url
      )

      create_app_usage_buildpack_event
    end

    def generate_start_event?
      # Change to app state is given priority over change to footprint as
      # we would like to generate only either start or stop event exactly
      # once during a state change. Also, if the app is not in started state
      # and/or is new, then the changes to the footprint shouldn't trigger a
      # billing event.
      started? && ((column_changed?(:state)) || (column_changed?(:droplet_hash)) || (!new? && footprint_changed?))
    end

    def generate_stop_event?
      # If app is not in started state and/or is new, then the changes
      # to the footprint shouldn't trigger a billing event.
      !new? &&
        (being_stopped? || (footprint_changed? && started?)) &&
        !has_stop_event_for_latest_run?
    end

    def in_suspended_org?
      space.in_suspended_org?
    end

    def being_stopped?
      column_changed?(:state) && stopped?
    end

    def being_started?
      column_changed?(:state) && started?
    end

    def scaling_operation?
      new? || !being_stopped?
    end

    def buildpack_changed?
      column_changed?(:buildpack)
    end

    def desired_instances
      started? ? instances : 0
    end

    def organization
      space && space.organization
    end

    def has_stop_event_for_latest_run?
      latest_run_id = AppStartEvent.filter(app_guid: guid).order(Sequel.desc(:id)).select_map(:app_run_id).first
      !!AppStopEvent.find(app_run_id: latest_run_id)
    end

    def before_destroy
      lock!
      self.state = 'STOPPED'
      super
    end

    def after_destroy
      super
      StackatoAppDrains.delete_all self
      AppStopEvent.create_from_app(self) unless initial_value(:state) == 'STOPPED' || has_stop_event_for_latest_run?
      create_app_usage_event
    end

    def after_destroy_commit
      super
      AppObserver.deleted(self)
    end

    def metadata_with_command
      result = metadata_without_command || self.metadata = {}
      result.merge!('command' => command) if command
      result
    end
    alias_method_chain :metadata, :command

    def command_with_fallback
      cmd = command_without_fallback
      cmd = (cmd.nil? || cmd.empty?) ? nil : cmd
      cmd || metadata_without_command && metadata_without_command['command']
    end
    alias_method_chain :command, :fallback

    def execution_metadata
      (current_droplet && current_droplet.execution_metadata) || ''
    end

    def detected_start_command
      (current_droplet && current_droplet.detected_start_command) || ''
    end

    def console=(c)
      self.metadata ||= {}
      self.metadata['console'] = c
    end

    def console
      # without the == true check, this expression can return nil if
      # the key doesn't exist, rather than false
      self.metadata && self.metadata['console'] == true
    end

    def debug=(d)
      self.metadata ||= {}
      # We don't support sending nil through API
      self.metadata['debug'] = (d == 'none') ? nil : d
    end

    def debug
      self.metadata && self.metadata['debug']
    end

    def droplet_count
      self.droplets_dataset.count
    end

    def environment_json_with_serialization=(env)
      self.environment_json_without_serialization = MultiJson.dump(env)
    end
    alias_method_chain :environment_json=, 'serialization'

    def environment_json_with_serialization
      string = environment_json_without_serialization
      return if string.blank?
      MultiJson.load string
    end
    alias_method_chain :environment_json, 'serialization'

    def system_env_json
      vcap_services
    end

    def vcap_application
      {
        limits: {
          mem: memory,
          disk: disk_quota,
          fds: file_descriptors
        },
        application_version: version,
        application_name: name,
        application_uris: uris,
        version: version,
        name: name,
        space_name: space.name,
        space_id: space_guid,
        uris: uris,
        users: nil
      }
    end

    def database_uri
      service_uris = service_bindings.map { |binding| binding.credentials['uri'] }.compact
      DatabaseUriGenerator.new(service_uris).database_uri
    end

    def validate_space(space)
      objection = Errors::InvalidRouteRelation.new(space.guid)

      raise objection unless routes.all? { |route| route.space_id == space.id }
      service_bindings.each { |binding| binding.validate_app_and_service_instance(self, binding.service_instance) }
    end

    def validate_route(route)
      objection = Errors::InvalidRouteRelation.new(route.guid)

      raise objection if route.nil?
      raise objection if space.nil?
      if route.space_id != space.id
        # Don't leak space names.  Users shouldn't see anything in other organizations.
        # Even if the existing route's space is in the current org, the current user might
        # not be a member of it, and therefore shouldn't see anything about it.
        raise Errors::InvalidRouteRelation.new("#{route.guid}: route '#{route.host}' is already defined in another space")
      end

      raise objection unless route.domain.usable_by_organization?(space.organization)

      if sso_enabled
        logger.debug "Registering oauth client for route #{route.inspect}"
        route.register_oauth_client
      end
    end

    def custom_buildpacks_enabled?
      !VCAP::CloudController::Config.config[:disable_custom_buildpacks]
    end

    def requested_instances
      default_instances = db_schema[:instances][:default].to_i
      instances ? instances : default_instances
    end

    def max_app_disk_in_mb
      VCAP::CloudController::Config.config[:maximum_app_disk_in_mb]
    end

    def validate_autoscaling_settings
      errors.add(:min_cpu_threshold, :invalid_value) \
        if !min_cpu_threshold.nil? && (min_cpu_threshold < 0 ||
                                         min_cpu_threshold > 100)
        
      errors.add(:max_cpu_threshold, :invalid_value) \
        if !max_cpu_threshold.nil? && (max_cpu_threshold < 0 ||
                                       max_cpu_threshold > 100)
        
      if (!min_cpu_threshold.nil? &&
          !max_cpu_threshold.nil? &&
          max_cpu_threshold < min_cpu_threshold)
        errors.add(:max_cpu_threshold, "< min_cpu_threshold".to_sym)
      end
        
      errors.add(:min_instances, :less_than_zero) \
        if !min_instances.nil? && min_instances < 1
        
      errors.add(:max_instances, :less_than_zero) \
        if !max_instances.nil? && max_instances < 1
        
      if (!min_instances.nil? &&
          !max_instances.nil? &&
          max_instances < min_instances)
        errors.add(:max_instances, "< min_instances".to_sym)
      end

      # First ensure that if only one of :min_instances and :max_instances
      # is specified, the requirement that min < max is maintained.
      if (changed_columns & [:min_instances, :max_instances]).size == 1
        if self.min_instances.nil? || self.max_instances.nil?
          # Set the unset attribute to the same value as the set one
          if changed_columns.include?(:min_instances)
            self.max_instances = self.min_instances
          else
            self.min_instances = self.min_instances
          end
        elsif self.min_instances > self.max_instances
          # Now complain if setting one breaks the requirement that min <= max
          if changed_columns.include?(:min_instances)
            raise Errors::ApiError.new_from_details("AppPackageInvalid", "specified value of min_instances: #{self.min_instances} > current value of max_instances: #{self.max_instances}")
          else
            raise Errors::ApiError.new_from_details("AppPackageInvalid", "specified value of max_instances: #{self.max_instances} < current value of min_instances: #{self.min_instances}")
          end
        end
      end
      # Now if we're switching into autoscale_enabled, make sure # instances
      # falls between the min and max ranges.
      if (autoscale_enabled &&
          (changed_columns & [:instances, :min_instances, :max_instances,
                              :autoscale_enabled]).size > 0)
        if !self.min_instances.nil? && self.instances < self.min_instances
          logger.debug("Raising # instances from specified #{instances} to min_instances #{min_instances}")
          self.instances = self.min_instances
        elsif !self.max_instances.nil? && self.instances > self.max_instances
          logger.debug("Lowering # instances from specified #{instances} to max_instances #{max_instances}")
          self.instances = self.max_instances
        end
      end
    end

    def max_app_disk_in_mb
      VCAP::CloudController::Config.config[:maximum_app_disk_in_mb]
    end

    # We need to overide this ourselves because we are really doing a
    # many-to-many with ServiceInstances and want to remove the relationship
    # to that when we remove the binding like sequel would do if the
    # relationship was explicly defined as such.  However, since we need to
    # annotate the join table with binding specific info, we manage the
    # many_to_one and one_to_many sides of the relationship ourself.  If there
    # is a sequel option that I couldn't see that provides this behavior, this
    # method could be removed in the future.  Note, the sequel docs explicitly
    # state that the correct way to overide the remove_bla functionality is to
    # do so with the _ prefixed private method like we do here.
    def _remove_service_binding(binding)
      binding.destroy
    end

    def self.user_visibility_filter(user)
      Sequel.or([
        [:space, user.spaces_dataset],
        [:space, user.managed_spaces_dataset],
        [:space, user.audited_spaces_dataset],
        [:apps__space_id, user.managed_organizations_dataset.join(
          :spaces, spaces__organization_id: :organizations__id
        ).select(:spaces__id)]
      ])
    end

    def needs_staging?
      package_hash && !staged? && started? && instances > 0
    end

    def staged?
      package_state == 'STAGED'
    end

    def staging_failed?
      package_state == 'FAILED'
    end

    def pending?
      package_state == 'PENDING'
    end

    def started?
      state == 'STARTED'
    end

    def stopped?
      state == 'STOPPED'
    end

    def uris
      routes.map(&:fqdn)
    end

    def mark_as_staged
      self.package_state = 'STAGED'
      self.package_pending_since = nil
    end

    def mark_as_failed_to_stage(reason='StagingError')
      app_from_db = self.class.find(:guid => guid)
      return unless app_from_db
      self.package_state = 'FAILED'
      self.staging_failed_reason = reason
      self.package_pending_since = nil
      save
    end

    def mark_for_restaging
      self.package_state = 'PENDING'
      self.staging_failed_reason = nil
      self.package_pending_since = Sequel::CURRENT_TIMESTAMP
    end

    def buildpack
      if admin_buildpack
        return admin_buildpack
      elsif super
        return CustomBuildpack.new(super)
      end

      AutoDetectionBuildpack.new
    end

    def buildpack=(buildpack_name)
      self.admin_buildpack = nil
      super(nil)
      admin_buildpack = Buildpack.find(name: buildpack_name.to_s)

      if admin_buildpack
        self.admin_buildpack = admin_buildpack
      elsif buildpack_name != '' # git url case
        super(buildpack_name)
      end
    end

    def buildpack_specified?
      !buildpack.is_a?(AutoDetectionBuildpack)
    end

    def custom_buildpack_url
      buildpack.url if buildpack.custom?
    end

    def docker_image=(value)
      value = fill_docker_string(value)
      super
      self.package_hash = value
    end

    def package_hash=(hash)
      super(hash)
      mark_for_restaging if column_changed?(:package_hash)
      self.package_updated_at = Sequel.datetime_class.now
    end

    def stack=(stack)
      mark_for_restaging unless new?
      super(stack)
    end

    def add_new_droplet(hash)
      self.droplet_hash = hash
      add_droplet(droplet_hash: hash)
      save
    end

    def current_droplet
      return nil unless droplet_hash
      # The droplet may not be in the droplet table as we did not backfill
      # existing droplets when creating the table.
      current_saved_droplet || Droplet.create(app: self, droplet_hash: droplet_hash)
    end

    def start!
      self.state = 'STARTED'
      save
    end

    def stop!
      self.state = 'STOPPED'
      save
    end

    def restage!
      stop!
      mark_for_restaging
      start!
    end

    # returns True if we need to update the DEA's with
    # associated URL's.
    # We also assume that the relevant methods in +Dea::Client+ will reset
    # this app's routes_changed state
    # @return [Boolean, nil]
    def dea_update_pending?
      staged? && started? && @routes_changed
    end

    def after_commit
      super

      begin
        AppObserver.updated(self)
      rescue Errors::ApiError => e
        UndoAppChanges.new(self).undo(previous_changes)
        raise e
      end
    end

    def allow_sudo?
      space && space.allow_sudo?
    end

    def to_hash(opts={})
      if !VCAP::CloudController::SecurityContext.admin? && !space.developers.include?(VCAP::CloudController::SecurityContext.current_user)
        opts.merge!(redact: %w(environment_json system_env_json))
      end
      super(opts)
    end

    def handle_add_route(route)
      mark_routes_changed(route)
      app_event_repository = Repositories::Runtime::AppEventRepository.new
      app_event_repository.record_map_route(self, route, SecurityContext.current_user, SecurityContext.current_user_email)
    end

    def handle_remove_route(route)
      mark_routes_changed(route)
      app_event_repository = Repositories::Runtime::AppEventRepository.new
      app_event_repository.record_unmap_route(self, route, SecurityContext.current_user, SecurityContext.current_user_email)
    end

    private

    def mark_routes_changed(_=nil)
      routes_already_changed = @routes_changed
      @routes_changed = true

      if diego?
        unless routes_already_changed
          App.db.after_commit do
            AppObserver.routes_changed(self)
            @routes_changed = false
          end
        end
      else
        set_new_version
        save
      end
    end

    # there's no concrete schema for what constitutes a valid docker
    # repo/image reference online at the moment, so make a best effort to turn
    # the passed value into a complete, plausible docker image reference:
    # registry-name:registry-port/[scope-name/]repo-name:tag-name
    def fill_docker_string(value)
      segs = value.split('/')
      segs[-1] = segs.last + ':latest' unless segs.last.include?(':')
      segs.join('/')
    end

    def metadata_deserialized
      deserialized_values[:metadata]
    end

    WHITELIST_SERVICE_KEYS = %w(name label tags plan credentials syslog_drain_url).freeze

    def service_binding_json(binding)
      vcap_service = {}
      WHITELIST_SERVICE_KEYS.each do |key|
        vcap_service[key] = binding[key.to_sym] if binding[key.to_sym]
      end
      vcap_service
    end

    def vcap_services
      services_hash = {}
      service_bindings.each do |sb|
        binding = ServiceBindingPresenter.new(sb).to_hash
        service = service_binding_json(binding)
        services_hash[binding[:label]] ||= []
        services_hash[binding[:label]] << service
      end
      { 'VCAP_SERVICES' => services_hash }
    end

    def generate_salt
      self.salt ||= VCAP::CloudController::Encryptor.generate_salt.freeze
    end

    def app_usage_event_repository
      @repository ||= Repositories::Runtime::AppUsageEventRepository.new
    end

    def create_app_usage_buildpack_event
      return unless staged? && started?
      app_usage_event_repository.create_from_app(self, 'BUILDPACK_SET')
    end

    def create_app_usage_event
      return unless app_usage_changed?
      app_usage_event_repository.create_from_app(self)
    end

    def app_usage_changed?
      previously_started = initial_value(:state) == 'STARTED'
      return true if previously_started != started?
      return true if started? && footprint_changed?
      false
    end

    def logger
      self.class.logger
    end

    def footprint_changed?
      (column_changed?(:production) || column_changed?(:memory) ||
        column_changed?(:instances))
    end

    class << self
      def logger
        @logger ||= Steno.logger('cc.models.app')
      end
    end
  end
  # rubocop:enable ClassLength
end
