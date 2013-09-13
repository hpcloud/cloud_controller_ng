require "spec_helper"

module VCAP::CloudController
  describe VCAP::CloudController::SpacesController, type: :controller do
    include_examples "uaa authenticated api", path: "/v2/spaces"
    include_examples "querying objects", path: "/v2/spaces", model: Models::Space, queryable_attributes: %w(name)
    include_examples "enumerating objects", path: "/v2/spaces", model: Models::Space
    include_examples "reading a valid object", path: "/v2/spaces", model: Models::Space, basic_attributes: %w(name organization_guid)
    include_examples "operations on an invalid object", path: "/v2/spaces"
    include_examples "creating and updating", path: "/v2/spaces", model: Models::Space, required_attributes: %w(name organization_guid), unique_attributes: %w(name organization_guid)
    include_examples "deleting a valid object", path: "/v2/spaces", model: Models::Space,
      one_to_many_collection_ids: {
        :apps => lambda { |space| Models::App.make(:space => space) },
        :service_instances => lambda { |space| Models::ManagedServiceInstance.make(:space => space) }
      },
      one_to_many_collection_ids_without_url: {
        :routes => lambda { |space| Models::Route.make(:space => space) },
        :default_users => lambda { |space|
          user = VCAP::CloudController::Models::User.make
          space.organization.add_user(user)
          space.add_developer(user)
          space.save
          user.default_space = space
          user.save
          user
        }
      }
    include_examples "collection operations", path: "/v2/spaces", model: Models::Space,
      one_to_many_collection_ids: {
        apps: lambda { |space| Models::App.make(space: space) },
        service_instances: lambda { |space| Models::ManagedServiceInstance.make(space: space) }
      },
      one_to_many_collection_ids_without_url: {
        routes: lambda { |space| Models::Route.make(space: space) },
        default_users: lambda { |space|
          user = VCAP::CloudController::Models::User.make
          space.organization.add_user(user)
          space.add_developer(user)
          space.save
          user.default_space = space
          user.save
          user
        }
      },
      many_to_one_collection_ids: {},
      many_to_many_collection_ids: {
        developers: lambda { |space| make_user_for_space(space) },
        managers: lambda { |space| make_user_for_space(space) },
        auditors: lambda { |space| make_user_for_space(space) },
        domains: lambda { |space| make_domain_for_space(space) }
      }


    describe "data integrity" do
      let(:space) { Models::Space.make }

      it "should not make strings into integers" do
        space.name = "1234"
        space.save
        get "/v2/spaces/#{space.guid}", {}, admin_headers
        decoded_response["entity"]["name"].should == "1234"
      end
    end

    describe "Permissions" do
      include_context "permissions"

      before do
        @obj_a = @space_a
        @obj_b = @space_b
      end

      let(:creation_req_for_a) do
        Yajl::Encoder.encode(:name => Sham.name, :organization_guid => @org_a.guid)
      end

      let(:update_req_for_a) do
        Yajl::Encoder.encode(:name => Sham.name)
      end

      describe "Org Level Permissions" do
        describe "OrgManager" do
          let(:member_a) { @org_a_manager }
          let(:member_b) { @org_b_manager }

          include_examples "permission enumeration", "OrgManager",
            :name => 'space',
            :path => "/v2/spaces",
            :enumerate => 1
        end

        describe "OrgUser" do
          let(:member_a) { @org_a_member }
          let(:member_b) { @org_b_member }

          include_examples "permission enumeration", "OrgUser",
            :name => 'space',
            :path => "/v2/spaces",
            :enumerate => 0
        end

        describe "BillingManager" do
          let(:member_a) { @org_a_billing_manager }
          let(:member_b) { @org_b_billing_manager }

          include_examples "permission enumeration", "BillingManager",
            :name => 'space',
            :path => "/v2/spaces",
            :enumerate => 0
        end

        describe "Auditor" do
          let(:member_a) { @org_a_auditor }
          let(:member_b) { @org_b_auditor }

          include_examples "permission enumeration", "Auditor",
            :name => 'space',
            :path => "/v2/spaces",
            :enumerate => 0
        end
      end

      describe "App Space Level Permissions" do
        describe "SpaceManager" do
          let(:member_a) { @space_a_manager }
          let(:member_b) { @space_b_manager }

          include_examples "permission enumeration", "SpaceManager",
            :name => 'space',
            :path => "/v2/spaces",
            :enumerate => 1
        end

        describe "Developer" do
          let(:member_a) { @space_a_developer }
          let(:member_b) { @space_b_developer }

          include_examples "permission enumeration", "Developer",
            :name => 'space',
            :path => "/v2/spaces",
            :enumerate => 1
        end

        describe "SpaceAuditor" do
          let(:member_a) { @space_a_auditor }
          let(:member_b) { @space_b_auditor }

          include_examples "permission enumeration", "SpaceAuditor",
            :name => 'space',
            :path => "/v2/spaces",
            :enumerate => 1
        end
      end
    end

    describe 'GET /v2/spaces/:guid/service_instances' do
      let(:space) { Models::Space.make }
      let(:developer) { make_developer_for_space(space) }

      context 'when filtering results' do
        it 'returns only matching results' do
          user_provided_service_instance_1 = Models::UserProvidedServiceInstance.make(space: space, name: 'provided service 1')
          user_provided_service_instance_2 = Models::UserProvidedServiceInstance.make(space: space, name: 'provided service 2')
          managed_service_instance_1 = Models::ManagedServiceInstance.make(space: space, name: 'managed service 1')
          managed_service_instance_2 = Models::ManagedServiceInstance.make(space: space, name: 'managed service 2')

          get "v2/spaces/#{space.guid}/service_instances", {'q' => 'name:provided service 1;', 'return_user_provided_service_instances' => true}, headers_for(developer)
          guids = decoded_response.fetch('resources').map { |service| service.fetch('metadata').fetch('guid') }
          guids.should == [user_provided_service_instance_1.guid]

          get "v2/spaces/#{space.guid}/service_instances", {'q' => 'name:managed service 1;', 'return_user_provided_service_instances' => true}, headers_for(developer)
          guids = decoded_response.fetch('resources').map { |service| service.fetch('metadata').fetch('guid') }
          guids.should == [managed_service_instance_1.guid]
        end
      end

      context 'when there are provided service instances' do
        let!(:user_provided_service_instance) { Models::UserProvidedServiceInstance.make(space: space) }
        let!(:managed_service_instance) { Models::ManagedServiceInstance.make(space: space) }

        describe 'when return_user_provided_service_instances is true' do
          it 'returns ManagedServiceInstances and UserProvidedServiceInstances' do
            get "v2/spaces/#{space.guid}/service_instances", {return_user_provided_service_instances: true}, headers_for(developer)

            guids = decoded_response.fetch('resources').map { |service| service.fetch('metadata').fetch('guid') }
            guids.should include(user_provided_service_instance.guid, managed_service_instance.guid)
          end

          it 'includes service_plan_url for managed service instaces' do
            get "/v2/spaces/#{space.guid}/service_instances", {return_user_provided_service_instances: true}, headers_for(developer)
            service_instances_response = decoded_response.fetch('resources')
            managed_service_instance_response = service_instances_response.detect {|si|
              si.fetch('metadata').fetch('guid') == managed_service_instance.guid
            }
            managed_service_instance_response.fetch('entity').fetch('service_plan_url').should be
            managed_service_instance_response.fetch('entity').fetch('space_url').should be
            managed_service_instance_response.fetch('entity').fetch('service_bindings_url').should be
          end
        end

        describe 'when return_user_provided_service_instances flag is not present' do
          it 'returns only the managed service instances' do
            get "/v2/spaces/#{space.guid}/service_instances", '', headers_for(developer)
            guids = decoded_response.fetch('resources').map { |service| service.fetch('metadata').fetch('guid') }
            guids.should =~ [managed_service_instance.guid]
          end

          it 'includes service_plan_url for managed service instaces' do
            get "/v2/spaces/#{space.guid}/service_instances", '', headers_for(developer)
            service_instances_response = decoded_response.fetch('resources')
            managed_service_instance_response = service_instances_response.detect {|si|
              si.fetch('metadata').fetch('guid') == managed_service_instance.guid
            }
            managed_service_instance_response.fetch('entity').fetch('service_plan_url').should be
            managed_service_instance_response.fetch('entity').fetch('space_url').should be
            managed_service_instance_response.fetch('entity').fetch('service_bindings_url').should be
          end
        end
      end

      describe 'Permissions' do
        include_context "permissions"
        shared_examples "disallow enumerating service instances" do |perm_name|
          describe "disallowing enumerating service instances" do
            it "disallows a user that only has #{perm_name} permission on the space" do
              get "/v2/spaces/#{@space_a.guid}/service_instances", {}, headers_for(member_a)

              last_response.status.should == 403
            end
          end
        end

        shared_examples "enumerating service instances" do |perm_name, opts|
          expected = opts.fetch(:expected)
          let(:path) { "/v2/spaces/#{@space_a.guid}/service_instances" }
          let!(:managed_service_instance) do
            Models::ManagedServiceInstance.make(
              space: @space_a,
            )
          end

          it "should return service instances to a user that has #{perm_name} permissions" do
            get path, {}, headers_for(member_a)

            last_response.should be_ok
            decoded_response["total_results"].should == expected
            guids = decoded_response["resources"].map { |o| o["metadata"]["guid"] }
            guids.should include(managed_service_instance.guid) if expected > 0
          end

          it "should not return a service instance to a user with the #{perm_name} permission on a different space" do
            get path, {}, headers_for(member_b)
            last_response.status.should eq(403)
          end
        end

        describe "Org Level" do
          describe "OrgManager" do
            include_examples(
              "enumerating service instances", "OrgManager",
              expected: 0,
            ) do
              let(:member_a) { @org_a_manager }
              let(:member_b) { @org_b_manager }
            end
          end

          describe "OrgUser" do
            include_examples(
              "disallow enumerating service instances", "OrgUser",
            ) do
              let(:member_a) { @org_a_member }
            end
          end

          describe "BillingManager" do
            include_examples(
              "disallow enumerating service instances", "BillingManager",
            ) do
              let(:member_a) { @org_a_billing_manager }
            end
          end

          describe "Auditor" do
            include_examples(
              "disallow enumerating service instances", "Auditor",
            ) do
              let(:member_a) { @org_a_auditor }
            end
          end
        end

        describe "App Space Level Permissions" do
          describe "SpaceManager" do
            include_examples(
              "enumerating service instances", "SpaceManager",
              expected: 0,
            ) do
              let(:member_a) { @space_a_manager }
              let(:member_b) { @space_b_manager }
            end
          end

          describe "Developer" do
            include_examples(
              "enumerating service instances", "Developer",
              expected: 1,
            ) do
              let(:member_a) { @space_a_developer }
              let(:member_b) { @space_b_developer }
            end
          end

          describe "SpaceAuditor" do
            include_examples(
              "enumerating service instances", "SpaceAuditor",
              expected: 1,
            ) do
              let(:member_a) { @space_a_auditor }
              let(:member_b) { @space_b_auditor }
            end
          end
        end
      end
    end
  end
end
