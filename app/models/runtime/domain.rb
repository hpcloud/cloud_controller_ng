module VCAP::CloudController
  class Domain < Sequel::Model
    DOMAIN_REGEX = /^[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}$/ix.freeze

    dataset.row_proc = proc do |row|
      if row[:owning_organization_id]
        PrivateDomain.call(row)
      else
        SharedDomain.call(row)
      end
    end

    dataset_module do
      def shared_domains
        filter(owning_organization_id: nil)
      end

      def private_domains
        filter(Sequel.~(owning_organization_id: nil))
      end
    end

    many_to_one :owning_organization, class: "VCAP::CloudController::Organization"
    one_to_many :routes

    add_association_dependencies routes: :destroy

    export_attributes :name, :owning_organization_guid
    import_attributes :name, :owning_organization_guid
    strip_attributes  :name

    def validate
      validates_presence :name
      validates_unique   :name

      validates_format DOMAIN_REGEX, :name
    end

    def self.user_visibility_filter(user)
      orgs = Organization.filter(Sequel.or(
        managers: [user],
        auditors: [user],
      ))

      Sequel.or(
        owning_organization: orgs,
        owning_organization_id: nil,
      )
    end

    def usable_by_organization?(org)
      shared? || owned_by?(org)
    end

    def shared?
      owning_organization.nil?
    end

    def owned_by?(org)
      owning_organization.id == org.id
    end
  end
end
