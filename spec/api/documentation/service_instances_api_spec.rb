require 'spec_helper'
require 'rspec_api_documentation/dsl'
require 'uri'

resource "Service Instances", :type => [:api, :legacy_api] do
  let(:admin_auth_header) { admin_headers["HTTP_AUTHORIZATION"] }
  let!(:service_instance) { VCAP::CloudController::ManagedServiceInstance.make }
  let(:guid) { service_instance.guid }

  authenticated_request

  describe "Standard endpoints" do
    standard_model_list :managed_service_instance, VCAP::CloudController::ServiceInstancesController, path: :service_instance
    standard_model_get :managed_service_instance, path: :service_instance, nested_attributes: [:space, :service_plan]
    standard_model_delete_without_async :service_instance

    post '/v2/service_instances/' do
      field :name, 'A name for the service instance', required: true, example_values: ['my-service-instance']
      field :service_plan_guid, 'The guid of the service plan to associate with the instance', required: true
      field :space_guid, 'The guid of the space in which the instance will be created', required: true
      field :gateway_data, 'Configuration information for the broker gateway in v1 services', required: false, deprecated: true

      example 'Creating a Service Instance' do
        space_guid = VCAP::CloudController::Space.make.guid
        service_plan_guid = VCAP::CloudController::ServicePlan.make(public: true).guid
        request_hash = {space_guid: space_guid, name: 'my-service-instance', service_plan_guid: service_plan_guid}

        client.post '/v2/service_instances', MultiJson.dump(request_hash, pretty: true), headers
        expect(status).to eq(201)
      end
    end

    put '/v2/service_instances/:guid' do
      let(:service_broker) { VCAP::CloudController::ServiceBroker.make }
      let(:service) { VCAP::CloudController::Service.make(service_broker: service_broker, plan_updateable: true) }
      let(:new_plan) { VCAP::CloudController::ServicePlan.make(service: service) }
      let(:old_plan) { VCAP::CloudController::ServicePlan.make(service: service) }
      let(:service_instance) { VCAP::CloudController::ManagedServiceInstance.make(service_plan: old_plan) }

      field :service_plan_guid, 'The new plan guid for the service instance', required: true, example_values: ['6c4bd80f-4593-41d1-a2c9-b20cb65ec76e']

      before do
        uri = URI(service_broker.broker_url)
        uri.user = service_broker.auth_username
        uri.password = service_broker.auth_password
        uri.path += "/v2/service_instances/#{service_instance.guid}/"
        stub_request(:patch, uri.to_s).to_return(:status => 200, :body => "", :headers => {})
      end

      example 'Updating the service plan a service instance' do
        request_json = { service_plan_guid: new_plan.guid }.to_json
        client.put "/v2/service_instances/#{service_instance.guid}", request_json, headers

        expect(status).to eq 201
        expect(service_instance.reload.service_plan.guid).to eq new_plan.guid
      end
    end
  end

  describe "Nested endpoints" do
    field :guid, "The guid of the Service Instance.", required: true

    describe "Service Bindings" do
      before do
        VCAP::CloudController::ServiceBinding.make(service_instance: service_instance)
      end

      standard_model_list :service_binding, VCAP::CloudController::ServiceBindingsController, outer_model: :service_instance
    end
  end

  get "/v2/service_instances/:guid/permissions" do
    example "Retrieving permissions on a Service Instance" do
      client.get "/v2/service_instances/#{service_instance.guid}/permissions", {}, headers
      expect(status).to eq(200)

      expect(parsed_response).to eql({'manage' => true})
    end
  end

  put '/v2/service_plans/:service_plan_guid/service_instances' do
    let(:new_plan) { VCAP::CloudController::ServicePlan.make }
    let(:old_plan) { service_instance.service_plan }
    let(:request_json) { {service_plan_guid: new_plan.guid}.to_json }

    field :service_plan_guid, "The guid of the plan to move the existing instances to", required: true, example_values: %w(6c4bd80f-4593-41d1-a2c9-b20cb65ec76e)

    example 'Migrate Service Instances from one Service Plan to another Service Plan (experimental)' do
      explanation <<-EOD
          Move all Service Instances for the service plan from the URL to the service plan in the request body
      EOD

      client.put "/v2/service_plans/#{old_plan.guid}/service_instances", request_json, headers

      expect(status).to eq(200)
      expect(parsed_response['changed_count']).to eq(1)
    end
  end
end
