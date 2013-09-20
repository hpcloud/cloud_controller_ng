require "spec_helper"

module VCAP::CloudController
  describe VCAP::CloudController::User, type: :model do
    it_behaves_like "a CloudController model", {
      :required_attributes          => :guid,
      :unique_attributes            => :guid,
      :many_to_zero_or_one => {
        :default_space => lambda { |user|
          org = user.organizations.first || Organization.make
          Space.make(:organization => org)
        }
      },
      :many_to_zero_or_more => {
        :organizations => lambda { |user| Organization.make },
        :managed_organizations => lambda { |user| Organization.make },
        :billing_managed_organizations => lambda { |user| Organization.make },
        :audited_organizations => lambda { |user| Organization.make },
        :spaces => lambda { |user|
          org = Organization.make
          user.add_organization(org)
          Space.make(:organization => org)
        }
      }
    }
  end
end
