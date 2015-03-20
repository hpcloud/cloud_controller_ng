require "spec_helper"

module VCAP::CloudController
  describe VCAP::CloudController::UsersController do
    describe "Query Parameters" do
      it { expect(described_class).to be_queryable_by(:space_guid) }
      it { expect(described_class).to be_queryable_by(:organization_guid) }
      it { expect(described_class).to be_queryable_by(:managed_organization_guid) }
      it { expect(described_class).to be_queryable_by(:billing_managed_organization_guid) }
      it { expect(described_class).to be_queryable_by(:audited_organization_guid) }
      it { expect(described_class).to be_queryable_by(:managed_space_guid) }
      it { expect(described_class).to be_queryable_by(:audited_space_guid) }
    end

    describe "Attributes" do
      it do
        expect(described_class).to have_creatable_attributes({
          guid: {type: "string", required: true},
          admin: {type: "bool", default: false},
          space_guids: {type: "[string]"},
          organization_guids: {type: "[string]"},
          managed_organization_guids: {type: "[string]"},
          billing_managed_organization_guids: {type: "[string]"},
          audited_organization_guids: {type: "[string]"},
          managed_space_guids: {type: "[string]"},
          audited_space_guids: {type: "[string]"},
          default_space_guid: {type: "string"},
        })
      end

      it do
        expect(described_class).to have_updatable_attributes({
          admin: {type: "bool"},
          space_guids: {type: "[string]"},
          organization_guids: {type: "[string]"},
          managed_organization_guids: {type: "[string]"},
          billing_managed_organization_guids: {type: "[string]"},
          audited_organization_guids: {type: "[string]"},
          managed_space_guids: {type: "[string]"},
          audited_space_guids: {type: "[string]"},
          default_space_guid: {type: "string"},
        })
      end
    end

    describe "Associations" do
      it do
        expect(described_class).to have_nested_routes(
          {
            spaces:                        [:get, :put, :delete],
            organizations:                 [:get, :put, :delete],
            managed_organizations:         [:get, :put, :delete],
            billing_managed_organizations: [:get, :put, :delete],
            audited_organizations:         [:get, :put, :delete],
            managed_spaces:                [:get, :put, :delete],
            audited_spaces:                [:get, :put, :delete],
          }
        )
      end
    end

    describe 'permissions' do
      include_context "permissions"
      before do
        @obj_a = member_a
      end

      context 'normal user' do
        before { @obj_b = member_b }
        let(:member_a) { @org_a_manager }
        let(:member_b) { @space_a_manager }
        include_examples "permission enumeration", "User",
                         :name => 'user',
                         :path => "/v2/users",
                         :enumerate => :not_allowed
      end

      context 'admin user' do
        let(:member_a) { @cf_admin }
        let(:enumeration_expectation_a) { User.order(:id).limit(50) }

        include_examples "permission enumeration", "Admin",
                         :name => 'user',
                         :path => "/v2/users",
                         :enumerate => Proc.new { User.count },
                         :permissions_overlap => true
      end
    end

    describe 'GET /v2/users/:guid/organizations' do
      let(:mgr) { User.make }
      let(:user) { User.make }
      let(:org) { Organization.make(manager_guids: [mgr.guid], user_guids: [user.guid]) }

      it 'allows the user' do
        get "/v2/users/#{user.guid}/organizations", '', headers_for(user)
        expect(last_response.status).to eq(200)
      end

      it 'disallows a different user' do
        get "/v2/users/#{mgr.guid}/organizations", '', headers_for(user)
        expect(last_response.status).to eq(403)
      end
    end
  end
end
