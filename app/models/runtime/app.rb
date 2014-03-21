require "cloud_controller/app_observer"
require 'digest/sha1'
require_relative "buildpack"

module VCAP::CloudController
  class App < Sequel::Model
    plugin :serialization

    APP_NAME_REGEX = /\A[[:print:]]+\Z/.freeze

    class InvalidRouteRelation < InvalidRelation
      def to_s
        "The URL was not available [route ID #{super}]"
      end
    end

    class InvalidBindingRelation < InvalidRelation;
    end

    class AlreadyDeletedError < StandardError;
    end

    class ApplicationMissing < RuntimeError
    end

    class << self
      def configure(custom_buildpacks_enabled)
        @custom_buildpacks_enabled = custom_buildpacks_enabled
      end

      def custom_buildpacks_enabled?
        @custom_buildpacks_enabled
      end
    end

    one_to_many :droplets
    one_to_many :service_bindings, :after_remove => :after_remove_binding
    one_to_many :events, :class => VCAP::CloudController::AppEvent
    many_to_one :admin_buildpack, class: VCAP::CloudController::Buildpack
    many_to_one :space
    many_to_one :stack
    many_to_many :routes, before_add: :validate_route, after_add: :mark_routes_changed, after_remove: :mark_routes_changed

    add_association_dependencies routes: :nullify, service_bindings: :destroy, events: :delete, droplets: :destroy

    default_order_by :name

    export_attributes :guid, :name, :production,
      :space_guid, :stack_guid, :buildpack, :detected_buildpack,
      :environment_json, :memory, :instances, :disk_quota,
      :state, :version, :command, :console, :debug,
      :staging_task_id, :package_state, :health_check_timeout, :system_env_json,
      :distribution_zone,
      :description, :sso_enabled, :restart_required, :autoscale_enabled,
      :min_cpu_threshold, :max_cpu_threshold, :min_instances, :max_instances

    import_attributes :name, :production,
      :space_guid, :stack_guid, :buildpack, :detected_buildpack,
      :environment_json, :memory, :instances, :disk_quota,
      :state, :command, :console, :debug,
      :staging_task_id, :service_binding_guids, :route_guids, :health_check_timeout,
      :distribution_zone,
      :description, :sso_enabled, :autoscale_enabled,
      :min_cpu_threshold, :max_cpu_threshold, :min_instances, :max_instances

    strip_attributes :name

    serialize_attributes :json, :metadata

    APP_STATES = %w[STOPPED STARTED].map(&:freeze).freeze
    PACKAGE_STATES = %w[PENDING STAGED FAILED].map(&:freeze).freeze

    CENSORED_FIELDS = [:encrypted_environment_json, :command, :environment_json]

    CENSORED_MESSAGE = "PRIVATE DATA HIDDEN".freeze

    def self.audit_hash(request_attrs)
      request_attrs.dup.tap do |changes|
        CENSORED_FIELDS.map(&:to_s).each do |censored|
          changes[censored] = CENSORED_MESSAGE if changes.has_key?(censored)
        end
      end
    end

    # marked as true on changing the associated routes, and reset by
    # +DeaClient.start+
    attr_accessor :routes_changed

    # Last staging response which will contain streaming log url
    attr_accessor :last_stager_response

    alias :kill_after_multiple_restarts? :kill_after_multiple_restarts

    def validate_buildpack_name_or_git_url
      bp = buildpack

      unless bp.valid?
        bp.errors.each do |err|
          errors.add(:buildpack, err)
        end
      end
    end

    def validate_buildpack_is_not_custom
      return unless column_changed?(:buildpack)

      if buildpack.custom?
        errors.add(:buildpack, "custom buildpacks are disabled")
      end
    end

    def validate
      validates_presence :name
      validates_app_name :name
      validates_presence :space
      validates_max_length 2048, :description, :allow_missing=>true
      validates_unique [:space_id, :name]
      validates_format APP_NAME_REGEX, :name

      validate_buildpack_name_or_git_url
      validate_buildpack_is_not_custom unless self.class.custom_buildpacks_enabled?

      validates_includes PACKAGE_STATES, :package_state, :allow_missing => true
      validates_includes APP_STATES, :state, :allow_missing => true

      validate_environment
      validate_metadata
      check_memory_quota
      validate_instances
      validate_autoscaling_settings
      validate_health_check_timeout
    end

    def before_create
      super
      set_new_version
    end

    def before_save
      if generate_start_event? && !package_hash
        raise VCAP::Errors::AppPackageInvalid.new(
          "bits have not been uploaded")
      end
      super

      self.stack ||= Stack.default
      self.memory ||= Config.config[:default_app_memory]
      set_new_version if version_needs_to_be_updated?

      update_requires_restart

      AppStopEvent.create_from_app(self) if generate_stop_event?
      AppStartEvent.create_from_app(self) if generate_start_event?

      adjust_route_sso_clients if sso_updated?
      adjust_instances
    end

    def after_save
      create_app_usage_event
      @changes = column_changes
      super
    end

    def create_app_usage_event
      return unless app_usage_changed?
      AppUsageEvent.create(state: state,
                           instance_count: instances,
                           memory_in_mb_per_instance: memory,
                           app_guid: guid,
                           app_name: name,
                           org_guid: space.organization_guid,
                           space_guid: space_guid,
                           space_name: space.name,
      )
    end

    def auditable_changes
      @changes || {}
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

    def adjust_instances
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
            raise VCAP::Errors::AppPackageInvalid.new("specified value of min_instances: #{self.min_instances} > current value of max_instances: #{self.max_instances}")
          else
            raise VCAP::Errors::AppPackageInvalid.new("specified value of max_instances: #{self.max_instances} > current value of min_instances: #{self.min_instances}")
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

    def version_needs_to_be_updated?
      # change version if:
      #
      # * transitioning to STARTED
      # * memory is changed
      # * routes are changed
      #
      # this is to indicate that the running state of an application has changed,
      # and that the system should converge on this new version.
      (column_changed?(:state) || column_changed?(:memory)) && started?
    end

    def set_new_version
      self.version = SecureRandom.uuid
    end

    def generate_start_event?
      # Change to app state is given priority over change to footprint as
      # we would like to generate only either start or stop event exactly
      # once during a state change. Also, if the app is not in started state
      # and/or is new, then the changes to the footprint shouldn't trigger a
      # billing event.
      started? && ((column_changed?(:state)) || (!new? && footprint_changed?))
    end

    def generate_stop_event?
      # If app is not in started state and/or is new, then the changes
      # to the footprint shouldn't trigger a billing event.
      !new? &&
        (being_stopped? || (footprint_changed? && started?)) &&
        !has_stop_event_for_latest_run?
    end

    def being_stopped?
      column_changed?(:state) && stopped?
    end

    def being_started?
      column_changed?(:state) && started?
    end

    def has_stop_event_for_latest_run?
      latest_run_id = AppStartEvent.filter(:app_guid => guid).order(Sequel.desc(:id)).select_map(:app_run_id).first
      !!AppStopEvent.find(:app_run_id => latest_run_id)
    end

    def footprint_changed?
      (column_changed?(:production) || column_changed?(:memory) ||
        column_changed?(:instances))
    end

    def before_destroy
      lock!
      self.state = "STOPPED"
      super
    end

    def after_destroy
      StackatoAppDrains.delete_all self
      AppStopEvent.create_from_app(self) unless initial_value(:state) == "STOPPED" || has_stop_event_for_latest_run?
      create_app_usage_event
    end

    def after_destroy_commit
      super
      AppObserver.deleted(self)
    end

    def command=(cmd)
      self.metadata ||= {}
      self.metadata["command"] = (cmd.nil? || cmd.empty?) ? nil : cmd
    end

    def command
      self.metadata && self.metadata["command"]
    end

    def console=(c)
      self.metadata ||= {}
      self.metadata["console"] = c
    end

    def console
      # without the == true check, this expression can return nil if
      # the key doesn't exist, rather than false
      self.metadata && self.metadata["console"] == true
    end

    def debug=(d)
      self.metadata ||= {}
      # We don't support sending nil through API
      self.metadata["debug"] = (d == "none") ? nil : d
    end

    def debug
      self.metadata && self.metadata["debug"]
    end

    # We sadly have to do this ourselves because the serialization plugin
    # doesn't play nice with the dirty plugin, and we want the dirty plugin
    # more
    def environment_json=(env)
      json = Yajl::Encoder.encode(env)
      generate_salt
      self.encrypted_environment_json =
        VCAP::CloudController::Encryptor.encrypt(json, salt)
    end

    def environment_json
      return unless encrypted_environment_json

      Yajl::Parser.parse(
        VCAP::CloudController::Encryptor.decrypt(
          encrypted_environment_json, salt))
    end

    def system_env_json
      vcap_services
    end

    def validate_environment
      return if environment_json.nil?
      unless environment_json.kind_of?(Hash)
        errors.add(:environment_json, :invalid_environment)
        return
      end
      environment_json.keys.each do |k|
        errors.add(:environment_json, "reserved_key:#{k}") if k =~ /^(vcap|vmc)_/i
      end
    rescue Yajl::ParseError
      errors.add(:environment_json, :invalid_json)
    end

    def validate_metadata
      m = deserialized_values[:metadata]
      return if m.nil?
      unless m.kind_of?(Hash)
        errors.add(:metadata, :invalid_metadata)
      end
    end

    def validate_route(route)
      objection = InvalidRouteRelation.new(route.guid)

      raise objection if route.nil?
      raise objection if space.nil?
      if route.space_id != space.id
        # Don't leak space names.  Users shouldn't see anything in other organizations.
        # Even if the existing route's space is in the current org, the current user might
        # not be a member of it, and therefore shouldn't see anything about it.
        raise InvalidRouteRelation.new("#{route.guid}: route '#{route.host}' is already defined in another space")
      end

      raise objection unless route.domain.usable_by_organization?(space.organization)

      if sso_enabled
        logger.debug "Registering oauth client for route #{route.inspect}"
        route.register_oauth_client
      end
    end

    def additional_memory_requested

      total_requested_memory = requested_memory * requested_instances

      return total_requested_memory if new?

      app_from_db = self.class.find(:guid => guid)
      if app_from_db.nil?
        self.class.logger.fatal("app.find.missing", :guid => guid, :self => self.inspect)
        raise ApplicationMissing, "Attempting to check memory quota. Should have been able to find app with guid #{guid}"
      end
      total_existing_memory = app_from_db[:memory] * app_from_db[:instances]
      total_requested_memory - total_existing_memory
    end

    def check_memory_quota
      errors.add(:memory, :zero_or_less) unless requested_memory > 0
      if space && (space.organization.memory_remaining < additional_memory_requested)
        errors.add(:memory, :quota_exceeded) if (new? || !being_stopped?)
      end
    end

    def total_existing_memory
      app_from_db = self.class.find(:guid => guid)
      app_from_db[:memory] * app_from_db[:instances]
    end

    def requested_instances
      default_instances = db_schema[:instances][:default].to_i
      instances ? instances : default_instances
    end

    def validate_instances
      if (requested_instances < 0)
        errors.add(:instances, :less_than_zero)
      end
    end

    def validate_health_check_timeout
      return unless health_check_timeout
      errors.add(:health_check_timeout, :less_than_zero) unless health_check_timeout >= 0

      if health_check_timeout > VCAP::CloudController::Config.config[:maximum_health_check_timeout]
        errors.add(:health_check_timeout, :maximum_exceeded)
      end
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
        [:apps__space_id, user.managed_organizations_dataset.join(:spaces, :spaces__organization_id => :organizations__id).select(:spaces__id)]
      ])
    end

    def needs_staging?
      package_hash && !staged? && started? && instances > 0
    end

    def staged?
      self.package_state == "STAGED"
    end

    def staging_failed?
      self.package_state == "FAILED"
    end

    def pending?
      self.package_state == "PENDING"
    end

    def started?
      self.state == "STARTED"
    end

    def stopped?
      self.state == "STOPPED"
    end

    def uris
      routes.map(&:fqdn)
    end

    def after_remove_binding(binding)
      mark_for_restaging
    end

    def mark_as_failed_to_stage
      app_from_db = self.class.find(:guid => guid)
      return unless app_from_db
      self.package_state = "FAILED"
      save
    end

    def mark_for_restaging(opts={})
      self.package_state = "PENDING"
      save if opts[:save]
    end

    def buildpack
      if admin_buildpack
        return admin_buildpack
      elsif super
        return GitBasedBuildpack.new(super)
      end

      AutoDetectionBuildpack.new
    end

    def buildpack=(buildpack)
      admin_buildpack = Buildpack.find(name: buildpack.to_s)
      if admin_buildpack
        self.admin_buildpack = admin_buildpack
        super(nil)
        return
      else
        self.admin_buildpack = nil
        super(buildpack)
      end
    end

    def package_hash=(hash)
      super(hash)
      mark_for_restaging if column_changed?(:package_hash)
    end

    def stack=(stack)
      mark_for_restaging unless new?
      super(stack)
    end

    def droplet_hash=(hash)
      if hash
        self.package_state = "STAGED"
      end
      super(hash)
    end

    def add_new_droplet(hash)
      self.droplet_hash = hash
      add_droplet(droplet_hash: hash)
      self.save
    end

    def current_droplet
      return nil unless droplet_hash
      self.droplets_dataset.filter(droplet_hash: droplet_hash).first ||
        Droplet.new(app: self, droplet_hash: self.droplet_hash)
    end

    def running_instances
      return 0 unless started?
      health_manager_client.healthy_instances(self)
    end

    # returns True if we need to update the DEA's with
    # associated URL's.
    # We also assume that the relevant methods in +DeaClient+ will reset
    # this app's routes_changed state
    # @return [Boolean, nil]
    def dea_update_pending?
      staged? && started? && @routes_changed
    end

    def after_commit
      super
      AppObserver.updated(self)
    end

    def allow_sudo?
      space && space.allow_sudo?
    end

    private

    WHITELIST_SERVICE_KEYS = %W[name label tags plan credentials].freeze
    def service_binding_json (binding)
      vcap_service = {}
      WHITELIST_SERVICE_KEYS.each do |key|
        vcap_service[key] = binding[key.to_sym] if binding[key.to_sym]
      end
      vcap_service
    end

    def vcap_services
      services_hash = {}
      self.service_bindings.each do |sb|
        binding = ServiceBindingPresenter.new(sb).to_hash
        service = service_binding_json(binding)
        services_hash[binding[:label]] ||= []
        services_hash[binding[:label]] << service
      end
      {"VCAP_SERVICES" => services_hash}
    end

    def health_manager_client
      CloudController::DependencyLocator.instance.health_manager_client
    end

    def requested_memory
      default_memory = VCAP::CloudController::Config.config[:default_app_memory]
      memory ? memory : default_memory
    end

    def mark_routes_changed(_)
      @routes_changed = true

      set_new_version
      save
    end

    def generate_salt
      self.salt ||= VCAP::CloudController::Encryptor.generate_salt.freeze
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

    class << self
      def logger
        @logger ||= Steno.logger("cc.models.app")
      end
    end
  end
end
