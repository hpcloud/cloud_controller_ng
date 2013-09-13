require "spec_helper"

module VCAP::CloudController
  describe ServicesController, :services, type: :controller do
    include_examples "uaa authenticated api", path: "/v2/services"
    include_examples "enumerating objects", path: "/v2/services", model: Models::Service
    include_examples "reading a valid object", path: "/v2/services", model: Models::Service,
      basic_attributes: %w(label provider url description version bindable tags)
    include_examples "operations on an invalid object", path: "/v2/services"
    include_examples "creating and updating", path: "/v2/services",
                     model: Models::Service,
                     required_attributes: %w(label provider url description version),
                     unique_attributes: %w(label provider),
                     extra_attributes: {extra: ->{Sham.extra}, bindable: false, tags: ["relational"]}
    include_examples "deleting a valid object", path: "/v2/services", model: Models::Service,
      one_to_many_collection_ids: {:service_plans => lambda { |service| Models::ServicePlan.make(:service => service) }},
      one_to_many_collection_ids_without_url: {}
    include_examples "collection operations", path: "/v2/services", model: Models::Service,
      one_to_many_collection_ids: {
        service_plans: lambda { |service| Models::ServicePlan.make(service: service) }
      },
      many_to_one_collection_ids: {},
      many_to_many_collection_ids: {}

    shared_examples "enumerate and read service only" do |perm_name|
      include_examples "permission enumeration", perm_name,
        :name => 'service',
        :path => "/v2/services",
        :permissions_overlap => true,
        :enumerate => 7
    end

    describe "Permissions" do
      include_context "permissions"

      before(:all) do
        reset_database
        5.times do
          Models::ServicePlan.make
        end
        @obj_a = Models::ServicePlan.make.service
        @obj_b = Models::ServicePlan.make.service
      end

      let(:creation_req_for_a) do
        Yajl::Encoder.encode(
          :label => Sham.label,
          :provider => Sham.provider,
          :url => Sham.url,
          :description => Sham.description,
          :version => Sham.version)
      end

      let(:update_req_for_a) do
        Yajl::Encoder.encode(:label => Sham.label)
      end

      describe "Org Level Permissions" do
        describe "OrgManager" do
          let(:member_a) { @org_a_manager }
          let(:member_b) { @org_b_manager }

          include_examples "enumerate and read service only", "OrgManager"
        end

        describe "OrgUser" do
          let(:member_a) { @org_a_member }
          let(:member_b) { @org_b_member }

          include_examples "enumerate and read service only", "OrgUser"
        end

        describe "BillingManager" do
          let(:member_a) { @org_a_billing_manager }
          let(:member_b) { @org_b_billing_manager }

          include_examples "enumerate and read service only", "BillingManager"
        end

        describe "Auditor" do
          let(:member_a) { @org_a_auditor }
          let(:member_b) { @org_b_auditor }

          include_examples "enumerate and read service only", "Auditor"
        end
      end

      describe "App Space Level Permissions" do
        describe "SpaceManager" do
          let(:member_a) { @space_a_manager }
          let(:member_b) { @space_b_manager }

          include_examples "enumerate and read service only", "SpaceManager"
        end

        describe "Developer" do
          let(:member_a) { @space_a_developer }
          let(:member_b) { @space_b_developer }

          include_examples "enumerate and read service only", "Developer"
        end

        describe "SpaceAuditor" do
          let(:member_a) { @space_a_auditor }
          let(:member_b) { @space_b_auditor }

          include_examples "enumerate and read service only", "SpaceAuditor"
        end
      end
    end

    describe "get /v2/services" do
      let(:user) {VCAP::CloudController::Models::User.make  }
      let (:headers) do
        headers_for(user)
      end

      before(:each) do
        reset_database
        @active = 3.times.map { Models::Service.make(:active => true).tap{|svc| Models::ServicePlan.make(:service => svc) } }
        @inactive = 2.times.map { Models::Service.make(:active => false).tap{|svc| Models::ServicePlan.make(:service => svc) } }
      end

      def decoded_guids
        decoded_response["resources"].map { |r| r["metadata"]["guid"] }
      end

      it "should get all services" do
        get "/v2/services", {}, headers
        last_response.should be_ok
        decoded_guids.should =~ (@active + @inactive).map(&:guid)
      end

      it "has a documentation URL field" do
        get "/v2/services", {}, headers
        decoded_response["resources"].first["entity"].keys.should include "documentation_url"
      end

      context "with an offering that has private plans" do
        before(:each) do
          @svc_all_private = @active.first
          @svc_all_private.service_plans.each{|plan| plan.update(:public => false) }
          @svc_one_public = @active.last
          Models::ServicePlan.make(service: @svc_one_public, public: false)
        end

        it "should remove the offering when I cannot see any of the plans" do
          get "/v2/services", {}, headers
          last_response.should be_ok
          decoded_guids.should include(@svc_one_public.guid)
          decoded_guids.should_not include(@svc_all_private.guid)
        end

        it "should return the offering when I can see at least one of the plans" do
          get "/v2/services", {}, admin_headers
          last_response.should be_ok
          decoded_guids.should include(@svc_one_public.guid)
          decoded_guids.should include(@svc_all_private.guid)
        end
      end

      describe "get /v2/services?q=active:<t|f>" do
        it "can remove inactive services" do
          # Sequel stores 'true' and 'false' as 't' and 'f' in sqlite, so with
          # sqlite, instead of 'true' or 'false', the parameter must be specified
          # as 't' or 'f'. But in postgresql, either way is ok.
          get "/v2/services?q=active:t", {}, headers
          last_response.should be_ok
          decoded_guids.should =~ @active.map(&:guid)
        end

        it "can only get inactive services" do
          get "/v2/services?q=active:f", {}, headers
          last_response.should be_ok
          decoded_guids.should =~ @inactive.map(&:guid)
        end
      end
    end

    describe 'POST', '/v2/services' do
      it 'creates a service' do
        unique_id = Sham.unique_id
        url = Sham.url
        documentation_url = Sham.url

        payload = ServicesController::CreateMessage.new(
          :unique_id => unique_id,
          :url => url,
          :documentation_url => documentation_url,
          :description => 'delightful service',
          :provider => 'widgets-inc',
          :label => 'foo-db',
          :version => 'v1.2.3'
        ).encode

        expect {
          post '/v2/services', payload, json_headers(admin_headers)
        }.to change(Models::Service, :count).by(1)

        last_response.status.should eq(201)
        guid = decoded_response.fetch('metadata').fetch('guid')

        service = Models::Service.last
        expect(service.guid).to eq(guid)
        expect(service.unique_id).to eq(unique_id)
        expect(service.url).to eq(url)
        expect(service.documentation_url).to eq(documentation_url)
        expect(service.description).to eq('delightful service')
        expect(service.provider).to eq('widgets-inc')
        expect(service.label).to eq('foo-db')
        expect(service.version).to eq('v1.2.3')
      end

      it 'makes the service bindable by default' do
        payload_without_bindable = ServicesController::CreateMessage.new(
          :label => Sham.label,
          :provider => Sham.provider,
          :url => Sham.url,
          :description => 'd',
          :version => 'v',
          :unique_id => Sham.unique_id,
        ).encode
        post "/v2/services", payload_without_bindable, json_headers(admin_headers)
        last_response.status.should eq(201)
        service_guid = decoded_response.fetch('metadata').fetch('guid')
        Models::Service.first(:guid => service_guid).bindable.should be_true
      end

      it 'creates the service with default tags' do
        payload_without_tags = ServicesController::CreateMessage.new(
          :label => Sham.label,
          :provider => Sham.provider,
          :url => Sham.url,
          :description => 'd',
          :version => 'v',
          :unique_id => Sham.unique_id
        ).encode
        post "/v2/services", payload_without_tags, json_headers(admin_headers)
        last_response.status.should eq(201)
        service_guid = decoded_response.fetch('metadata').fetch('guid')
        Models::Service.first(:guid => service_guid).tags.should == []
      end

      it 'creates the service with specified tags' do
        payload_without_tags = ServicesController::CreateMessage.new(
          :label => Sham.label,
          :provider => Sham.provider,
          :url => Sham.url,
          :description => 'd',
          :version => 'v',
          :unique_id => Sham.unique_id,
          :tags => ["relational"]
        ).encode
        post "/v2/services", payload_without_tags, json_headers(admin_headers)
        last_response.status.should eq(201)
        service_guid = decoded_response.fetch('metadata').fetch('guid')
        Models::Service.first(:guid => service_guid).tags.should == ["relational"]
      end
    end

    describe "PUT", "/v2/services/:guid" do
      it "ignores the unique_id attribute" do
        service = Models::Service.make
        old_unique_id = service.unique_id
        new_unique_id = old_unique_id.reverse
        payload = Yajl::Encoder.encode({"unique_id" => new_unique_id})

        put "/v2/services/#{service.guid}", payload, json_headers(admin_headers)

        service.reload
        expect(last_response.status).to be == 201
        expect(service.unique_id).to be == old_unique_id
      end
    end
  end
end
