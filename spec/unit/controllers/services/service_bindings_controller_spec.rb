require 'spec_helper'

module VCAP::CloudController
  describe ServiceBindingsController do
    describe 'Query Parameters' do
      it { expect(described_class).to be_queryable_by(:app_guid) }
      it { expect(described_class).to be_queryable_by(:service_instance_guid) }
    end

    describe 'Attributes' do
      it do
        expect(described_class).to have_creatable_attributes({
          binding_options: { type: 'hash', default: {} },
          app_guid: { type: 'string', required: true },
          service_instance_guid: { type: 'string', required: true }
        })
      end

      it do
        expect(described_class).to have_updatable_attributes({
          binding_options: { type: 'hash' },
          app_guid: { type: 'string' },
          service_instance_guid: { type: 'string' }
        })
      end
    end

    CREDENTIALS = { 'foo' => 'bar' }

    def fake_app_staging(app)
      app.package_hash = 'abc'
      app.droplet_hash = 'def'
      app.save
      expect(app.needs_staging?).to eq(false)
    end

    let(:broker_client) { double('broker client') }

    before do
      allow(broker_client).to receive(:bind) do |binding|
        binding.broker_provided_id = Sham.guid
        binding.credentials = CREDENTIALS
      end
      allow(broker_client).to receive(:unbind)
      allow_any_instance_of(Service).to receive(:client).and_return(broker_client)
    end

    describe 'Permissions' do
      include_context 'permissions'

      before do
        @app_a = AppFactory.make(space: @space_a)
        @service_instance_a = ManagedServiceInstance.make(space: @space_a)
        @obj_a = ServiceBinding.make(
          app: @app_a,
          service_instance: @service_instance_a
        )

        @app_b = AppFactory.make(space: @space_b)
        @service_instance_b = ManagedServiceInstance.make(space: @space_b)
        @obj_b = ServiceBinding.make(
          app: @app_b,
          service_instance: @service_instance_b
        )
      end

      describe 'Org Level Permissions' do
        describe 'OrgManager' do
          let(:member_a) { @org_a_manager }
          let(:member_b) { @org_b_manager }

          include_examples 'permission enumeration', 'OrgManager',
            name: 'service binding',
            path: '/v2/service_bindings',
            enumerate: 0
        end

        describe 'OrgUser' do
          let(:member_a) { @org_a_member }
          let(:member_b) { @org_b_member }

          include_examples 'permission enumeration', 'OrgUser',
            name: 'service binding',
            path: '/v2/service_bindings',
            enumerate: 0
        end

        describe 'BillingManager' do
          let(:member_a) { @org_a_billing_manager }
          let(:member_b) { @org_b_billing_manager }

          include_examples 'permission enumeration', 'BillingManager',
            name: 'service binding',
            path: '/v2/service_bindings',
            enumerate: 0
        end

        describe 'Auditor' do
          let(:member_a) { @org_a_auditor }
          let(:member_b) { @org_b_auditor }

          include_examples 'permission enumeration', 'Auditor',
            name: 'service binding',
            path: '/v2/service_bindings',
            enumerate: 0
        end
      end

      describe 'App Space Level Permissions' do
        describe 'SpaceManager' do
          let(:member_a) { @space_a_manager }
          let(:member_b) { @space_b_manager }

          include_examples 'permission enumeration', 'SpaceManager',
            name: 'service binding',
            path: '/v2/service_bindings',
            enumerate: 0
        end

        describe 'Developer' do
          let(:member_a) { @space_a_developer }
          let(:member_b) { @space_b_developer }

          include_examples 'permission enumeration', 'Developer',
            name: 'service binding',
            path: '/v2/service_bindings',
            enumerate: 1
        end

        describe 'SpaceAuditor' do
          let(:member_a) { @space_a_auditor }
          let(:member_b) { @space_b_auditor }

          include_examples 'permission enumeration', 'SpaceAuditor',
            name: 'service binding',
            path: '/v2/service_bindings',
            enumerate: 1
        end
      end
    end

    describe 'create' do
      context 'for user provided instances' do
        let(:space) { Space.make }
        let(:developer) { make_developer_for_space(space) }
        let(:application) { AppFactory.make(space: space) }
        let(:service_instance) { UserProvidedServiceInstance.make(space: space) }
        let(:params) do
          {
            'app_guid' => application.guid,
            'service_instance_guid' => service_instance.guid
          }
        end

        it 'creates a service binding with the provided binding options' do
          binding_options = Sham.binding_options
          body =  params.merge('binding_options' => binding_options).to_json
          post '/v2/service_bindings', body, headers_for(developer)

          expect(last_response.status).to eq(201)
          expect(ServiceBinding.last.binding_options).to eq(binding_options)
        end
      end

      context 'for managed instances' do
        let(:instance) { ManagedServiceInstance.make }
        let(:space) { instance.space }
        let(:plan) { instance.service_plan }
        let(:service) { plan.service }
        let(:developer) { make_developer_for_space(space) }
        let(:app_obj) { AppFactory.make(space: space) }

        it 'binds a service instance to an app' do
          req = {
            app_guid: app_obj.guid,
            service_instance_guid: instance.guid
          }.to_json

          post '/v2/service_bindings', req, json_headers(headers_for(developer))
          expect(last_response.status).to eq(201)

          expect(broker_client).to have_received(:bind)

          binding = ServiceBinding.last
          expect(binding.credentials).to eq(CREDENTIALS)
        end

        it 'creates an audit event upon binding' do
          req = {
            app_guid: app_obj.guid,
            service_instance_guid: instance.guid
          }

          email = 'email@example.com'
          post '/v2/service_bindings', req.to_json, json_headers(headers_for(developer, email: email))

          service_binding = ServiceBinding.last

          event = Event.first(type: 'audit.service_binding.create')
          expect(event.actor_type).to eq('user')
          expect(event.timestamp).to be
          expect(event.actor).to eq(developer.guid)
          expect(event.actor_name).to eq(email)
          expect(event.actee).to eq(service_binding.guid)
          expect(event.actee_type).to eq('service_binding')
          expect(event.actee_name).to eq('')
          expect(event.space_guid).to eq(space.guid)
          expect(event.space_id).to eq(space.id)
          expect(event.organization_guid).to eq(space.organization.guid)

          expect(event.metadata).to include({
            'request' => {
              'service_instance_guid' => req[:service_instance_guid],
              'app_guid' => req[:app_guid]
            }
          })
        end

        it 'unbinds the service instance when an exception is raised' do
          req = MultiJson.dump(
            app_guid: app_obj.guid,
            service_instance_guid: instance.guid
          )

          allow_any_instance_of(ServiceBinding).to receive(:save).and_raise

          post '/v2/service_bindings', req, json_headers(headers_for(developer))
          expect(broker_client).to have_received(:unbind).with(an_instance_of(ServiceBinding))
          expect(last_response.status).to eq(500)
        end

        context 'when attempting to bind to an unbindable service' do
          before do
            service.bindable = false
            service.save

            req = {
              app_guid: app_obj.guid,
              service_instance_guid: instance.guid
            }.to_json

            post '/v2/service_bindings', req, json_headers(headers_for(developer))
          end

          it 'raises UnbindableService error' do
            hash_body = JSON.parse(last_response.body)
            expect(hash_body['error_code']).to eq('CF-UnbindableService')
            expect(last_response.status).to eq(400)
          end

          it 'does not send a bind request to broker' do
            expect(broker_client).to_not have_received(:bind)
          end
        end

        context 'when the app is invalid' do
          context 'because app_guid is invalid' do
            let(:req) do
              {
                app_guid: 'THISISWRONG',
                service_instance_guid: instance.guid
              }.to_json
            end

            it 'returns CF-AppNotFound' do
              post '/v2/service_bindings', req, json_headers(headers_for(developer))

              hash_body = JSON.parse(last_response.body)
              expect(hash_body['error_code']).to eq('CF-AppNotFound')
              expect(last_response.status).to eq(404)
            end
          end
        end

        context 'when the service instance is invalid' do
          context 'because service_instance_guid is invalid' do
            let(:req) do
              {
                app_guid: app_obj.guid,
                service_instance_guid: 'THISISWRONG'
              }.to_json
            end

            before do
              service.save
            end

            it 'returns CF-ServiceInstanceNotFound error' do
              post '/v2/service_bindings', req, json_headers(headers_for(developer))

              hash_body = JSON.parse(last_response.body)
              expect(hash_body['error_code']).to eq('CF-ServiceInstanceNotFound')
              expect(last_response.status).to eq(404)
            end
          end

          context 'because the service instance is destroyed after controller validation and before binding save' do
            let(:req) do
              {
                app_guid: app_obj.guid,
                service_instance_guid: 'THISISWRONG'
              }.to_json
            end

            before do
              allow(broker_client).to receive(:bind).and_return(true)
              allow_any_instance_of(ServiceBinding).to receive(:client).and_return(broker_client)
            end

            it 'returns CF-ServiceInstanceNotFound error' do
              post '/v2/service_bindings', req, json_headers(headers_for(developer))

              hash_body = JSON.parse(last_response.body)
              expect(hash_body['error_code']).to eq('CF-ServiceInstanceNotFound')
              expect(last_response.status).to eq(404)
            end
          end
        end

        describe 'binding errors' do
          subject(:make_request) do
            req = {
              app_guid: app_obj.guid,
              service_instance_guid: instance.guid
            }.to_json
            post '/v2/service_bindings', req, json_headers(headers_for(developer))
          end

          context 'when attempting to bind and the service binding already exists' do
            before do
              ServiceBinding.make(app: app_obj, service_instance: instance)
            end

            it 'returns a ServiceBindingAppServiceTaken error' do
              make_request
              expect(last_response.status).to eq(400)
              expect(decoded_response['error_code']).to eq('CF-ServiceBindingAppServiceTaken')
            end

            it 'does not send a bind request to broker' do
              make_request
              expect(broker_client).not_to have_received(:bind)
            end
          end

          context 'when the v2 broker returns a 409' do
            before do
              service.service_broker = ServiceBroker.make
              allow(broker_client).to receive(:bind) do
                uri = 'http://broker.url.com'
                method = 'PUT'
                response = double(:response, code: 409, body: '{}')
                raise VCAP::Services::ServiceBrokers::V2::Errors::ServiceBrokerConflict.new(uri, method, response)
              end
            end

            it 'returns a 409' do
              make_request
              expect(last_response.status).to eq 409
            end

            it 'returns a ServiceBrokerConflict error' do
              make_request
              expect(decoded_response['error_code']).to eq 'CF-ServiceBrokerConflict'
            end
          end

          context 'when the v2 broker returns any other error' do
            before do
              service.service_broker = ServiceBroker.make
              allow(broker_client).to receive(:bind) do
                uri = 'http://broker.url.com'
                method = 'PUT'
                response = double(:response, code: 500, body: '{"description": "ERROR MESSAGE HERE"}')
                raise VCAP::Services::ServiceBrokers::V2::Errors::ServiceBrokerBadResponse.new(uri, method, response)
              end
            end

            it 'passes through the error message' do
              make_request
              expect(last_response.status).to eq 502
              expect(decoded_response['description']).to match /ERROR MESSAGE HERE/
            end
          end
        end
      end
    end

    describe 'DELETE', '/v2/service_bindings/:service_binding_guid' do
      let(:service_binding) { ServiceBinding.make }
      let(:developer) { make_developer_for_space(service_binding.service_instance.space) }

      it 'returns an empty response body' do
        delete "/v2/service_bindings/#{service_binding.guid}", '', json_headers(headers_for(developer))
        expect(last_response.status).to eq 204
        expect(last_response.body).to be_empty
      end

      it 'unbinds a service instance from an app' do
        delete "/v2/service_bindings/#{service_binding.guid}", '', json_headers(headers_for(developer))
        expect(ServiceBinding.find(guid: service_binding.guid)).to be_nil
        expect(broker_client).to have_received(:unbind).with(service_binding)
      end

      it 'records an audit event after the binding has been deleted' do
        email = 'email@example.com'
        space = service_binding.service_instance.space

        delete "/v2/service_bindings/#{service_binding.guid}", '', json_headers(headers_for(developer, email: email))

        event = Event.first(type: 'audit.service_binding.delete')
        expect(event.actor_type).to eq('user')
        expect(event.timestamp).to be
        expect(event.actor).to eq(developer.guid)
        expect(event.actor_name).to eq(email)
        expect(event.actee).to eq(service_binding.guid)
        expect(event.actee_type).to eq('service_binding')
        expect(event.actee_name).to eq('')
        expect(event.space_guid).to eq(space.guid)
        expect(event.space_id).to eq(space.id)
        expect(event.organization_guid).to eq(space.organization.guid)

        expect(event.metadata).to include({
          'request' => {}
        })
      end

      context 'with ?async=true' do
        it 'returns a job id' do
          delete "/v2/service_bindings/#{service_binding.guid}?async=true", '', json_headers(headers_for(developer))
          expect(last_response.status).to eq 202
          expect(decoded_response['entity']['guid']).to be
          expect(decoded_response['entity']['status']).to eq 'queued'
        end
      end
    end

    describe 'GET', '/v2/service_bindings?inline-relations-depth=1', regression: true do
      it 'returns both user provided and managed service instances' do
        managed_service_instance = ManagedServiceInstance.make
        ServiceBinding.make(service_instance: managed_service_instance)

        user_provided_service_instance = UserProvidedServiceInstance.make
        ServiceBinding.make(service_instance: user_provided_service_instance)

        get '/v2/service_bindings?inline-relations-depth=1', {}, admin_headers
        expect(last_response.status).to eql(200)

        service_bindings = decoded_response['resources']
        service_instance_guids = service_bindings.map do |res|
          res['entity']['service_instance']['metadata']['guid']
        end

        expect(service_instance_guids).to match_array([
          managed_service_instance.guid,
          user_provided_service_instance.guid,
        ])
      end
    end
  end
end
