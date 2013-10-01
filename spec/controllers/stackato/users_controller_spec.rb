require "spec_helper"

module VCAP::CloudController
  describe VCAP::CloudController::StackatoUsersController, type: :controller do
    context 'logged in as an admin' do
      before do
        VCAP::CloudController::SecurityContext.stub(:token).and_return({'scope' => ['cloud_controller.admin']})
      end

      include_examples "uaa authenticated api", path: "/v2/stackato/users"
      # include_examples "enumerating objects", path: "/v2/users", model: User
      # include_examples "reading a valid object", path: "/v2/users", model: User, basic_attributes: []
      # include_examples "operations on an invalid object", path: "/v2/users"
      # include_examples "creating and updating", path: "/v2/users", model: User, required_attributes: %w(guid), unique_attributes: %w(guid)
      # include_examples "deleting a valid object", path: "/v2/users", model: User, one_to_many_collection_ids: {}, one_to_many_collection_ids_without_url: {}
      # include_examples "collection operations", path: "/v2/users", model: User,
      #   one_to_many_collection_ids: {},
      #   many_to_one_collection_ids: {
      #     :default_space => lambda { |user|
      #       org = user.organizations.first || Organization.make
      #       Space.make(:organization => org)
      #     }
      #   },
      #   many_to_many_collection_ids: {
      #     organizations: lambda { |user| Organization.make },
      #     managed_organizations: lambda { |user| Organization.make },
      #     billing_managed_organizations: lambda { |user| Organization.make },
      #     audited_organizations: lambda { |user| Organization.make },
      #     spaces: lambda { |user|
      #       org = user.organizations.first || Organization.make
      #       Space.make(organization: org)
      #     },
      #     managed_spaces: lambda { |user|
      #       org = user.organizations.first || Organization.make
      #       Space.make(organization: org)
      #     },
      #     audited_spaces: lambda { |user|
      #       org = user.organizations.first || Organization.make
      #       Space.make(organization: org)
      #     }
      #   }
    end

  end
end
