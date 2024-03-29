require "uaa/scim"

module VCAP::CloudController
  class User < Sequel::Model
    include StackatoUserCreation

    class InvalidOrganizationRelation < VCAP::Errors::InvalidRelation; end

    no_auto_guid

    many_to_many :organizations,
      before_remove: :validate_organization_roles

    many_to_one :default_space, key: :default_space_id, class: 'VCAP::CloudController::Space'

    many_to_many :managed_organizations,
      class: 'VCAP::CloudController::Organization',
      join_table: 'organizations_managers',
      right_key: :organization_id, reciprocal: :managers,
      before_add: :validate_organization,
      before_remove: proc { |user, org| org.manager_guids.count > 1 }

    many_to_many :billing_managed_organizations,
      class: 'VCAP::CloudController::Organization',
      join_table: 'organizations_billing_managers',
      right_key: :organization_id,
      reciprocal: :billing_managers,
      before_add: :validate_organization

    many_to_many :audited_organizations,
      class: 'VCAP::CloudController::Organization',
      join_table: 'organizations_auditors',
      right_key: :organization_id, reciprocal: :auditors,
      before_add: :validate_organization

    many_to_many :spaces,
      class: 'VCAP::CloudController::Space',
      join_table: 'spaces_developers',
      right_key: :space_id, reciprocal: :developers

    many_to_many :managed_spaces,
      class: 'VCAP::CloudController::Space',
      join_table: 'spaces_managers',
      right_key: :space_id, reciprocal: :managers

    many_to_many :audited_spaces,
      class: 'VCAP::CloudController::Space',
      join_table: 'spaces_auditors',
      right_key: :space_id, reciprocal: :auditors

    add_association_dependencies organizations: :nullify
    add_association_dependencies managed_organizations: :nullify
    add_association_dependencies audited_spaces: :nullify
    add_association_dependencies billing_managed_organizations: :nullify
    add_association_dependencies audited_organizations: :nullify
    add_association_dependencies spaces: :nullify
    add_association_dependencies managed_spaces: :nullify

    export_attributes :admin, :active, :default_space_guid, :guid, :username

    import_attributes :guid, :admin, :active, :username,
                      :organization_guids,
                      :managed_organization_guids,
                      :billing_managed_organization_guids,
                      :audited_organization_guids,
                      :space_guids,
                      :managed_space_guids,
                      :audited_space_guids,
                      :default_space_guid

    def validate
      validates_presence :guid
      validates_unique :guid
    end

    def before_save
      super
      cache_username
    end

    def cache_username 
      begin
        # Cache the users username so we can provide username searching/filtering in the api
        result = scim_client.get(:user, guid)
        self.username = result["username"]
      rescue CF::UAA::NotFound
        # User doesn't exist in AOK. This shouldn't happen but it will crop up if the user is being created in the CC before AOK.
      rescue CF::UAA::BadResponse  # Bug 105615
        # Do nothing
      end
    end

    def validate_organization(org)
      unless org && organizations.include?(org)
        raise InvalidOrganizationRelation.new(org.guid)
      end
    end

    def validate_organization_roles(org)
      if org && (managed_organizations.include?(org) || billing_managed_organizations.include?(org) || audited_organizations.include?(org))
        raise InvalidOrganizationRelation.new(org.guid)
      end
    end

    def admin?
      admin
    end

    def active?
      active
    end

    def remove_spaces(space)
      remove_space space
      remove_managed_space space
      remove_audited_space space
    end

    def self.user_visibility_filter(_)
      full_dataset_filter
    end
  end
end
