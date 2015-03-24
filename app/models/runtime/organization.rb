module VCAP::CloudController
  class Organization < Sequel::Model
    ORG_NAME_REGEX = /\A[[:alnum:][:punct:][:print:]]+\Z/.freeze
    ORG_STATUS_VALUES = %w(active suspended)

    one_to_many :spaces

    one_to_many :service_instances,
                dataset: -> { VCAP::CloudController::ServiceInstance.filter(space: spaces) }

    one_to_many :managed_service_instances,
                dataset: -> { VCAP::CloudController::ServiceInstance.filter(space: spaces, is_gateway_service: true) }

    one_to_many :apps,
                dataset: -> { App.filter(space: spaces) }

    one_to_many :app_events,
                dataset: -> { VCAP::CloudController::AppEvent.filter(app: apps) }

    one_to_many(
      :private_domains,
      key: :owning_organization_id,
      before_add: proc { |org, private_domain| private_domain.addable_to_organization!(org) }
    )

    one_to_many :service_plan_visibilities
    many_to_one :quota_definition

    one_to_many :domains,
                dataset: -> { VCAP::CloudController::Domain.shared_or_owned_by(id) },
                remover: ->(legacy_domain) { legacy_domain.destroy if legacy_domain.owning_organization_id == id },
                clearer: -> { remove_all_private_domains },
                adder: ->(legacy_domain) { legacy_domain.addable_to_organization!(self) },
                eager_loader: proc { |eo|
                  id_map = {}
                  eo[:rows].each do |org|
                    org.associations[:domains] = []
                    id_map[org.id] = org
                  end

                  ds = Domain.shared_or_owned_by(id_map.keys)
                  ds = ds.eager(eo[:associations]) if eo[:associations]
                  ds = eo[:eager_block].call(ds) if eo[:eager_block]

                  ds.all do |domain|
                    if domain.shared?
                      id_map.each { |_, org| org.associations[:domains] << domain }
                    else
                      id_map[domain.owning_organization_id].associations[:domains] << domain
                    end
                  end
                }

    one_to_many :space_quota_definitions,
                before_add: proc { |org, quota| quota.organization.id == org.id }

    add_association_dependencies(
      spaces: :destroy,
      service_instances: :destroy,
      private_domains: :destroy,
      service_plan_visibilities: :destroy,
      space_quota_definitions: :destroy
    )

    define_user_group :users
    define_user_group :managers, 
                      reciprocal: :managed_organizations
    define_user_group :billing_managers, reciprocal: :billing_managed_organizations
    define_user_group :auditors, reciprocal: :audited_organizations

    strip_attributes :name

    export_attributes :name, :billing_enabled, :quota_definition_guid, :status, :is_default
    import_attributes :name, :billing_enabled,
                      :user_guids, :manager_guids, :billing_manager_guids,
                      :auditor_guids, :private_domain_guids, :quota_definition_guid, :status,
                      :domain_guids, :is_default

    def remove_user(user)
      can_remove = ([user.spaces, user.audited_spaces, user.managed_spaces].flatten & spaces).empty?
      raise VCAP::Errors::ApiError.new_from_details('AssociationNotEmpty', 'user', 'spaces in the org') unless can_remove
      super(user)
    end

    def remove_user_recursive(user)
      ([user.spaces, user.audited_spaces, user.managed_spaces].flatten & spaces).each do |space|
        user.remove_spaces space
      end
    end

    def self.user_visibility_filter(user)
      Sequel.or(
        managers: [user],
        users: [user],
        billing_managers: [user],
        auditors: [user])
    end

    def before_save
      if column_changed?(:billing_enabled) && billing_enabled?
        @is_billing_enabled = true
      end

      # Only an admin can change the is_default property of an organization, if the 'user_org_creation' FeatureFlag is
      # enabled we still need to allow for org creation while disallowing the user to change the is_default property.
      user_org_creation_enabled = FeatureFlag.enabled?('user_org_creation')
      if column_changed?(:is_default) && (!user_org_creation_enabled ||
          user_org_creation_enabled && VCAP::CloudController::SecurityContext.admin?)
        raise Errors::ApiError.new_from_details("NotAuthorized") unless VCAP::CloudController::SecurityContext.admin?
        # if this org is being made the default we need to 1) remove default from other orgs and 2) ensure the default space belong to this org
        if self.is_default
          # remove default space if it doesn't belong to this org
          default_space = Space.where(:is_default => true).first
          if default_space
            if default_space.organization_guid != self.guid
              default_space.update(:is_default => false)
            end
          end
          # remove default from all other orgs
          Organization.where(:is_default => true).update(:is_default => false)
        # if this org was the default, but is no longer, then we need to ensure the default space is removed as well
        else
          Space.where(:is_default => true).update(:is_default => false)
        end
      end

      validate_quota

      super
    end

    def after_save
      super
      # We cannot start billing events without the guid being assigned to the org.
      if @is_billing_enabled
        OrganizationStartEvent.create_from_org(self)
        # retroactively emit start events for services
        spaces.map(&:service_instances).flatten.each do |si|
          ServiceCreateEvent.create_from_service_instance(si)
        end
        spaces.map(&:apps).flatten.each do |app|
          AppStartEvent.create_from_app(app) if app.started?
        end
      end
    end

    def validate
      validates_presence :name
      validates_unique :name
      validates_format ORG_NAME_REGEX, :name
      validates_includes ORG_STATUS_VALUES, :status, allow_missing: true
    end

    def has_remaining_memory(mem)
      memory_remaining >= mem
    end

    def active?
      status == 'active'
    end

    def suspended?
      status == 'suspended'
    end

    def billing_enabled?
      billing_enabled
    end

    def allow_sudo?
      quota_definition && quota_definition.allow_sudo
    end

    private

    def validate_quota_on_create
      return if quota_definition

      if QuotaDefinition.default.nil?
        err_msg = Errors::ApiError.new_from_details('QuotaDefinitionNotFound', QuotaDefinition.default_quota_name).message
        raise Errors::ApiError.new_from_details('OrganizationInvalid', err_msg)
      end
      self.quota_definition_id = QuotaDefinition.default.id
    end

    def validate_quota_on_update
      if column_changed?(:quota_definition_id) && quota_definition.nil?
        err_msg = Errors::ApiError.new_from_details('QuotaDefinitionNotFound', 'null').message
        raise Errors::ApiError.new_from_details('OrganizationInvalid', err_msg)
      end
    end

    def validate_quota
      new? ? validate_quota_on_create : validate_quota_on_update
    end

    def memory_remaining
      memory_used = apps_dataset.where(state: 'STARTED').sum(Sequel.*(:memory, :instances)) || 0
      quota_definition.memory_limit - memory_used
    end
  end
end
