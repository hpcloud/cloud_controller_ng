module VCAP::CloudController
  class Space < Sequel::Model
    class InvalidDeveloperRelation < VCAP::Errors::InvalidRelation; end
    class InvalidAuditorRelation < VCAP::Errors::InvalidRelation; end
    class InvalidManagerRelation < VCAP::Errors::InvalidRelation; end
    class InvalidSpaceQuotaRelation < VCAP::Errors::InvalidRelation; end
    class UnauthorizedAccessToPrivateDomain < RuntimeError; end
    class OrganizationAlreadySet < RuntimeError; end

    SPACE_NAME_REGEX = /\A[[:alnum:][:punct:][:print:]]+\Z/.freeze

    define_user_group :developers, reciprocal: :spaces, before_add: :validate_developer
    define_user_group :managers, reciprocal: :managed_spaces, before_add: :validate_manager
    define_user_group :auditors, reciprocal: :audited_spaces, before_add: :validate_auditor

    many_to_one :organization, before_set: :validate_change_organization
    one_to_many :apps
    one_to_many :app_models, primary_key: :guid, key: :space_guid
    one_to_many :events
    one_to_many :service_instances
    one_to_many :managed_service_instances
    one_to_many :routes
    many_to_many :security_groups,
    dataset: -> {
      SecurityGroup.left_join(:security_groups_spaces, security_group_id: :id).
        where(Sequel.or(security_groups_spaces__space_id: id, security_groups__running_default: true))
    },
    eager_loader: ->(spaces_map) {
      space_ids = spaces_map[:id_map].keys
      # Set all associations to nil so if no records are found, we don't do another query when somebody tries to load the association
      spaces_map[:rows].each { |space| space.associations[:security_groups] = [] }

      default_security_groups = SecurityGroup.where(running_default: true).all

      SecurityGroupsSpace.where(space_id: space_ids).eager(:security_group).all do |security_group_space|
        space = spaces_map[:id_map][security_group_space.space_id].first
        space.associations[:security_groups] << security_group_space.security_group
      end

      spaces_map[:rows].each do |space|
        space.associations[:security_groups] += default_security_groups
        space.associations[:security_groups].uniq!
      end
    }

    one_to_many :app_events,
      dataset: -> { AppEvent.filter(app: apps) }

    one_to_many :default_users, class: 'VCAP::CloudController::User', key: :default_space_id

    one_to_many :domains,
      dataset: -> { organization.domains_dataset },
      adder: ->(domain) { domain.addable_to_organization!(organization) },
      eager_loader: proc { |eo|
        id_map = {}
        eo[:rows].each do |space|
          space.associations[:domains] = []
          id_map[space.organization_id] ||= []
          id_map[space.organization_id] << space
        end

        ds = Domain.shared_or_owned_by(id_map.keys)
        ds = ds.eager(eo[:associations]) if eo[:associations]
        ds = eo[:eager_block].call(ds) if eo[:eager_block]

        ds.all do |domain|
          if domain.shared?
            id_map.each { |_, spaces| spaces.each { |space| space.associations[:domains] << domain } }
          else
            id_map[domain.owning_organization_id].each { |space| space.associations[:domains] << domain }
          end
        end
      }

    many_to_one :space_quota_definition

    add_association_dependencies(
      default_users: :nullify,
      apps: :destroy,
      routes: :destroy,
      events: :nullify,
      security_groups: :nullify,
    )

    export_attributes :name, :organization_guid, :is_default, :space_quota_definition_guid

    import_attributes :name, :organization_guid, :developer_guids,
      :manager_guids, :auditor_guids, :is_default, :security_group_guids, :space_quota_definition_guid

    strip_attributes :name

    dataset_module do
      def having_developers(*users)
        join(:spaces_developers, spaces_developers__space_id: :spaces__id).
          where(spaces_developers__user_id: users.map(&:id)).select_all(:spaces)
      end
    end

    def in_organization?(user)
      organization && organization.users.include?(user)
    end

    def before_save
      if (new? && is_default) || (!new? && column_changed?(:is_default))
        raise Errors::ApiError.new_from_details("NotAuthorized") unless VCAP::CloudController::SecurityContext.admin?
        # if this space is being made the default we need to 1) remove default from all other spaces and 2) ensure the default org is the org that owns this space
        if self.is_default
          # ensure the owning org becomes the new default (if it isn't already)
          default_org = Organization.where(:is_default => true).first
          if default_org && default_org.guid != self.organization_guid
            default_org.update(:is_default => false)
          end
          Organization.where(:guid => self.organization_guid).update(:is_default => true)
          # remove default from all other spaces
          Space.where(:is_default => true).update(:is_default => false)
        end
      end
    end

    def validate
      validates_presence :name
      validates_max_length 64, :name
      validates_presence :organization
      validates_unique [:organization_id, :name]
      validates_format SPACE_NAME_REGEX, :name

      if space_quota_definition && space_quota_definition.organization.guid != organization.guid
        errors.add(:space_quota_definition, :invalid_organization)
      end
    end

    def validate_developer(user)
      raise InvalidDeveloperRelation.new(user.guid) unless in_organization?(user)
    end

    def validate_manager(user)
      raise InvalidManagerRelation.new(user.guid) unless in_organization?(user)
    end

    def validate_auditor(user)
      raise InvalidAuditorRelation.new(user.guid) unless in_organization?(user)
    end

    def allow_sudo?
      organization && organization.allow_sudo?
    end

    def validate_change_organization(new_org)
      raise OrganizationAlreadySet unless organization.nil? || organization.guid == new_org.guid
    end

    def self.user_visibility_filter(user)
      Sequel.or(
        organization: user.managed_organizations_dataset,
        developers: [user],
        managers: [user],
        auditors: [user]
      )
    end

    def has_remaining_memory(mem)
      return true unless space_quota_definition
      memory_remaining >= mem
    end

    def in_suspended_org?
      organization.suspended?
    end

    private

    def memory_remaining
      memory_used = apps_dataset.where(state: 'STARTED').sum(Sequel.*(:memory, :instances)) || 0
      space_quota_definition.memory_limit - memory_used
    end
  end
end
