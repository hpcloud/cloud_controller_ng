module VCAP::CloudController
  class Space < Sequel::Model
    class InvalidDeveloperRelation < VCAP::Errors::InvalidRelation; end
    class InvalidAuditorRelation < VCAP::Errors::InvalidRelation; end
    class InvalidManagerRelation < VCAP::Errors::InvalidRelation; end
    class UnauthorizedAccessToPrivateDomain < RuntimeError; end

    SPACE_NAME_REGEX = /\A[[:alnum:][:punct:][:print:]]+\Z/.freeze

    define_user_group :developers, reciprocal: :spaces, before_add: :validate_developer
    define_user_group :managers, reciprocal: :managed_spaces, before_add: :validate_manager
    define_user_group :auditors, reciprocal: :audited_spaces, before_add: :validate_auditor

    many_to_one :organization
    one_to_many :apps
    one_to_many :events
    one_to_many :service_instances
    one_to_many :managed_service_instances
    one_to_many :routes

    one_to_many :app_events,
                dataset: -> { AppEvent.filter(app: apps) }

    one_to_many :default_users, class: "VCAP::CloudController::User", key: :default_space_id

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

    add_association_dependencies default_users: :nullify, apps: :destroy, service_instances: :destroy, routes: :destroy, events: :nullify

    default_order_by  :name

    export_attributes :name, :organization_guid, :is_default

    import_attributes :name, :organization_guid, :developer_guids,
                      :manager_guids, :auditor_guids, :is_default

    strip_attributes  :name

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
        raise Errors::NotAuthorized unless VCAP::CloudController::SecurityContext.admin?
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
      validates_unique   [:organization_id, :name]
      validates_format SPACE_NAME_REGEX, :name
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

    def validate_domain(domain)
      return if domain && domain.owning_organization.nil? || organization.nil?

      unless domain.owning_organization_id == organization.id
        raise InvalidDomainRelation.new(domain.guid)
      end
    end

    def add_inheritable_domains
      return unless organization

      organization.domains.each do |d|
        add_domain_by_guid(d.guid) unless d.owning_organization
      end
    end

    def allow_sudo?
      organization && organization.allow_sudo?
    end

    def self.user_visibility_filter(user)
      Sequel.or(
        organization: user.managed_organizations_dataset,
        developers: [user],
        managers: [user],
        auditors: [user]
      )
    end

    def in_suspended_org?
      organization.suspended?
    end
  end
end
