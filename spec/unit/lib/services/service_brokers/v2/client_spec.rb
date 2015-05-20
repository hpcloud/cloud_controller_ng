require 'spec_helper'

module VCAP::Services::ServiceBrokers::V2
  describe Client do
    let(:service_broker) { VCAP::CloudController::ServiceBroker.make }

    let(:client_attrs) {
      {
        url: service_broker.broker_url,
        auth_username: service_broker.auth_username,
        auth_password: service_broker.auth_password,
      }
    }

    subject(:client) { Client.new(client_attrs) }

    let(:http_client) { instance_double(HttpClient) }
    let(:orphan_mitigator) { instance_double(OrphanMitigator, cleanup_failed_provision: nil, cleanup_failed_bind: nil) }

    before do
      allow(HttpClient).to receive(:new).
        with(url: service_broker.broker_url, auth_username: service_broker.auth_username, auth_password: service_broker.auth_password).
        and_return(http_client)

      allow(VCAP::Services::ServiceBrokers::V2::OrphanMitigator).to receive(:new).
        and_return(orphan_mitigator)

      allow(http_client).to receive(:url).and_return(service_broker.broker_url)
    end

    describe '#initialize' do
      it 'creates HttpClient with correct attrs' do
        Client.new(client_attrs.merge(extra_arg: 'foo'))

        expect(HttpClient).to have_received(:new).with(client_attrs)
      end
    end

    describe '#catalog' do
      let(:service_id) { Sham.guid }
      let(:service_name) { Sham.name }
      let(:service_description) { Sham.description }
      let(:plan_id) { Sham.guid }
      let(:plan_name) { Sham.name }
      let(:plan_description) { Sham.description }

      let(:response_data) do
        {
          'services' => [
            {
              'id' => service_id,
              'name' => service_name,
              'description' => service_description,
              'plans' => [
                {
                  'id' => plan_id,
                  'name' => plan_name,
                  'description' => plan_description
                }
              ]
            }
          ]
        }
      end

      let(:path) { '/v2/catalog' }
      let(:catalog_response) { HttpResponse.new(code: code, body: catalog_response_body, message: message) }
      let(:catalog_response_body) { response_data.to_json }
      let(:code) { '200' }
      let(:message) { 'OK' }

      before do
        allow(http_client).to receive(:get).with(path).and_return(catalog_response)
      end

      it 'returns a catalog' do
        expect(client.catalog).to eq(response_data)
      end
    end

    describe '#provision' do
      let(:plan) { VCAP::CloudController::ServicePlan.make }
      let(:space) { VCAP::CloudController::Space.make }
      let(:service_instance_operation) { VCAP::CloudController::ServiceInstanceOperation.make }
      let(:instance) do
        VCAP::CloudController::ManagedServiceInstance.make(
          service_plan: plan,
          space: space
        )
      end

      let(:response_data) do
        {
          'dashboard_url' => 'foo'
        }
      end

      let(:path) { "/v2/service_instances/#{instance.guid}" }
      let(:response) { HttpResponse.new(code: code, body: response_body, message: message) }
      let(:response_body) { response_data.to_json }
      let(:code) { '201' }
      let(:message) { 'Created' }

      before do
        allow(http_client).to receive(:put).and_return(response)
        allow(http_client).to receive(:delete).and_return(response)

        instance.service_instance_operation = service_instance_operation
      end

      it 'makes a put request with correct path' do
        client.provision(instance)

        expect(http_client).to have_received(:put).
          with(path, anything)
      end

      context 'when the caller passes the accepts_incomplete flag' do
        let(:path) { "/v2/service_instances/#{instance.guid}?accepts_incomplete=true" }

        it 'adds the flag to the path of the service broker request' do
          client.provision(instance, accepts_incomplete: true)

          expect(http_client).to have_received(:put).
            with(path, anything)
        end
      end

      it 'makes a put request with correct message' do
        client.provision(instance)

        expect(http_client).to have_received(:put).with(
          anything,
          service_id:        instance.service.broker_provided_id,
          plan_id:           instance.service_plan.broker_provided_id,
          organization_guid: instance.organization.guid,
          space_guid:        instance.space.guid
        )
      end

      it 'returns the attributes to update on a service instance' do
        attributes, _ = client.provision(instance)
        # ensure updating attributes and saving to service instance works
        instance.save_with_operation(attributes)

        expect(instance.dashboard_url).to eq('foo')
      end

      it 'defaults the state to "succeeded"' do
        attributes, _ = client.provision(instance)

        expect(attributes[:last_operation][:state]).to eq('succeeded')
      end

      it 'leaves the description blank' do
        attributes, _ = client.provision(instance)

        expect(attributes[:last_operation][:description]).to eq('')
      end

      it 'DEPRECATED, maintain for database not null constraint: sets the credentials on the instance' do
        attributes, _ = client.provision(instance)

        expect(attributes[:credentials]).to eq({})
      end

      it 'passes arbitrary params in the broker request' do
        request_attrs = {
          'parameters' => {
            'some_param' => 'some-value'
          }
        }

        client.provision(instance, request_attrs: request_attrs)
        expect(http_client).to have_received(:put).with(path, hash_including(parameters: request_attrs['parameters']))
      end

      context 'when the broker returns 204 (No Content)' do
        let(:code) { '204' }
        let(:client) { Client.new(client_attrs) }

        it 'throws ServiceBrokerBadResponse and initiates orphan mitigation' do
          expect {
            client.provision(instance)
          }.to raise_error(Errors::ServiceBrokerBadResponse)

          expect(orphan_mitigator).to have_received(:cleanup_failed_provision).with(client_attrs, instance)
        end
      end

      context 'when the broker returns no state or the state is succeeded' do
        let(:response_data) do
          {
            'last_operation' => {}
          }
        end

        it 'return immediately with the broker response' do
          client = Client.new(client_attrs)
          attributes, _ = client.provision(instance, accepts_incomplete: true)

          expect(attributes[:last_operation][:type]).to eq('create')
          expect(attributes[:last_operation][:state]).to eq('succeeded')
          expect(attributes[:last_operation][:description]).to eq('')
        end
      end

      context 'when the broker returns no description' do
        let(:response_data) do
          {
            'last_operation' => { 'state' => 'succeeded' }
          }
        end

        it 'return immediately with the broker response' do
          client = Client.new(client_attrs)
          attributes, _ = client.provision(instance, accepts_incomplete: true)

          expect(attributes[:last_operation][:type]).to eq('create')
          expect(attributes[:last_operation][:state]).to eq('succeeded')
          expect(attributes[:last_operation][:description]).to eq('')
        end
      end

      context 'when the broker returns the state as `in progress`' do
        let(:code) { 202 }
        let(:message) { 'Accepted' }
        let(:response_data) do
          {
            last_operation: {
              state: 'in progress',
              description: '10% done'
            },
          }
        end

        it 'return immediately with the broker response' do
          client = Client.new(client_attrs)
          attributes, _ = client.provision(instance, accepts_incomplete: true)

          expect(attributes[:last_operation][:type]).to eq('create')
          expect(attributes[:last_operation][:state]).to eq('in progress')
          expect(attributes[:last_operation][:description]).to eq('10% done')
        end

        it 'returns the interval for polling the operation state' do
          _, polling_interval = client.provision(instance)
          expect(polling_interval).to eq 60
        end

        it 'does not enqueue a polling job' do
          expect {
            client.provision(instance)
          }.not_to change { Delayed::Job.count }
        end

        context 'and async_poll_interval_seconds is set by the broker' do
          let(:broker_polling_interval) { '120' }
          let(:response_data) do
            {
              last_operation: {
                state: 'in progress',
                description: '10% done',
                async_poll_interval_seconds: broker_polling_interval
              },
            }
          end

          it 'parses the value as an integer and returns the polling interval' do
            _, polling_interval = client.provision(instance, accepts_incomplete: true)
            expect(polling_interval).to eq 120
          end
        end
      end

      context 'when the broker returns the state as failed' do
        let(:code) { 400 }
        let(:message) { 'Failed' }
        let(:response_data) do
          {
            description: '100% failed'
          }
        end

        it 'raises an error' do
          client = Client.new(client_attrs)
          expect { client.provision(instance, accepts_incomplete: true) }.to raise_error(Errors::ServiceBrokerRequestRejected)
        end

        it 'does not enqueue a polling job' do
          client.provision(instance, accepts_incomplete: true) rescue nil
          Timecop.freeze(Time.now + 1.hour) do
            expect(Delayed::Worker.new.work_off).to eq([0, 0])
          end
        end
      end

      context 'when provision fails' do
        let(:uri) { 'some-uri.com/v2/service_instances/some-guid' }
        let(:response) { HttpResponse.new(code: nil, body: nil, message: nil) }

        context 'due to an http client error' do
          let(:http_client) { instance_double(HttpClient) }

          before do
            allow(http_client).to receive(:put).and_raise(error)
          end

          context 'Errors::ServiceBrokerApiTimeout error' do
            let(:error) { Errors::ServiceBrokerApiTimeout.new(uri, :put, Timeout::Error.new) }

            it 'propagates the error and follows up with a deprovision request' do
              expect {
                client.provision(instance)
              }.to raise_error(Errors::ServiceBrokerApiTimeout)

              expect(orphan_mitigator).to have_received(:cleanup_failed_provision).with(client_attrs, instance)
            end
          end
        end

        context 'due to a response parser error' do
          let(:response_parser) { instance_double(ResponseParser) }

          before do
            allow(response_parser).to receive(:parse).and_raise(error)
            allow(VCAP::Services::ServiceBrokers::V2::ResponseParser).to receive(:new).and_return(response_parser)
          end

          context 'Errors::ServiceBrokerApiTimeout error' do
            let(:error) { Errors::ServiceBrokerApiTimeout.new(uri, :put, Timeout::Error.new) }

            it 'propagates the error and follows up with a deprovision request' do
              expect {
                client.provision(instance)
              }.to raise_error(Errors::ServiceBrokerApiTimeout)

              expect(orphan_mitigator).to have_received(:cleanup_failed_provision).
                with(client_attrs, instance)
            end
          end

          context 'ServiceBrokerBadResponse error' do
            let(:error) { Errors::ServiceBrokerBadResponse.new(uri, :put, response) }

            it 'propagates the error and follows up with a deprovision request' do
              expect {
                client.provision(instance)
              }.to raise_error(Errors::ServiceBrokerBadResponse)

              expect(orphan_mitigator).to have_received(:cleanup_failed_provision).with(client_attrs, instance)
            end
          end

          context 'ServiceBrokerResponseMalformed error' do
            let(:error) { Errors::ServiceBrokerResponseMalformed.new(uri, :put, response, '') }

            it 'propagates the error and follows up with a deprovision request' do
              expect {
                client.provision(instance)
              }.to raise_error(Errors::ServiceBrokerResponseMalformed)

              expect(orphan_mitigator).to have_received(:cleanup_failed_provision).with(client_attrs, instance)
            end

            context 'when the status code was a 200' do
              let(:response) { HttpResponse.new(code: 200, body: nil, message: nil) }

              it 'does not initiate orphan mitigation' do
                expect {
                  client.provision(instance)
                }.to raise_error(Errors::ServiceBrokerResponseMalformed)

                expect(orphan_mitigator).not_to have_received(:cleanup_failed_provision).with(client_attrs, instance)
              end
            end
          end
        end
      end
    end

    describe '#fetch_service_instance_state' do
      let(:plan) { VCAP::CloudController::ServicePlan.make }
      let(:space) { VCAP::CloudController::Space.make }
      let(:instance) do
        VCAP::CloudController::ManagedServiceInstance.make(
          service_plan: plan,
          space: space
        )
      end

      let(:response_data) do
        {
          'dashboard_url' => 'bar',
          'last_operation' => {
            'state' => 'succeeded',
            'description' => '100% created'
          }
        }
      end

      let(:path) { "/v2/service_instances/#{instance.guid}" }
      let(:response) { HttpResponse.new(code: code, message: message, body: response_body) }
      let(:response_body) { response_data.to_json }
      let(:code) { '200' }
      let(:message) { 'OK' }

      before do
        instance.save_with_operation(
          last_operation: { type: 'create' }
        )
        allow(http_client).to receive(:get).and_return(response)
      end

      it 'makes a put request with correct path' do
        client.fetch_service_instance_state(instance)

        expect(http_client).to have_received(:get).
          with("/v2/service_instances/#{instance.guid}")
      end

      it 'returns the attributes to update the service instance model' do
        attrs = client.fetch_service_instance_state(instance)
        expected_attrs = response_data.symbolize_keys
        expected_attrs[:last_operation] = response_data['last_operation'].symbolize_keys
        expect(attrs).to eq(expected_attrs)
      end

      context 'when the broker returns 410' do
        let(:code) { '410' }
        let(:message) { 'GONE' }
        let(:response_data) do
          {}
        end

        context 'when the last operation type is `delete`' do
          before do
            instance.save_with_operation(
              last_operation: {
                type: 'delete',
              }
            )
          end

          it 'returns attributes to indicate the service instance was deleted' do
            attrs = client.fetch_service_instance_state(instance)
            expect(attrs).to include(
              last_operation: {
                state: 'succeeded',
                description: ''
              }
            )
          end
        end

        context 'with any other operation type' do
          before do
            instance.save_with_operation(
              last_operation: {
                type: 'update'
              }
            )
          end

          it 'returns attributes to indicate the service instance operation failed' do
            attrs = client.fetch_service_instance_state(instance)
            expect(attrs).to include(
              last_operation: {
                state: 'failed',
                description: ''
              }
            )
          end
        end
      end
    end

    describe '#update_service_plan' do
      let(:old_plan) { VCAP::CloudController::ServicePlan.make }
      let(:new_plan) { VCAP::CloudController::ServicePlan.make }

      let(:space) { VCAP::CloudController::Space.make }
      let(:last_operation) do
        VCAP::CloudController::ServiceInstanceOperation.make(
          type: 'create',
          state: 'succeeded'
        )
      end

      let(:instance) do
        VCAP::CloudController::ManagedServiceInstance.make(
          service_plan: old_plan,
          space: space
        )
      end

      let(:service_plan_guid) { new_plan.guid }

      let(:path) { "/v2/service_instances/#{instance.guid}" }
      let(:code) { 200 }
      let(:message) { 'OK' }
      let(:response_body) { response_data.to_json }
      let(:response_data) { {} }

      before do
        response = HttpResponse.new(code: code, body: response_body, message: message)
        allow(http_client).to receive(:patch).and_return(response)
        instance.service_instance_operation = last_operation
      end

      it 'makes a patch request with the new service plan' do
        client.update_service_plan(instance, new_plan)

        expect(http_client).to have_received(:patch).with(
          anything,
          {
            plan_id:	new_plan.broker_provided_id,
            previous_values: {
              plan_id: old_plan.broker_provided_id,
              service_id: old_plan.service.broker_provided_id,
              organization_id: instance.organization.guid,
              space_id: instance.space.guid
            }
          }
        )
      end

      it 'makes a patch request to the correct path' do
        client.update_service_plan(instance, new_plan)

        expect(http_client).to have_received(:patch).with(path, anything)
      end

      context 'when the caller passes arbitrary parameters' do
        it 'includes the parameters in the request to the broker' do
          client.update_service_plan(instance, new_plan, parameters: { myParam: 'some-value' })

          expect(http_client).to have_received(:patch).with(
            anything,
            {
              plan_id:	new_plan.broker_provided_id,
              parameters: { myParam: 'some-value' },
              previous_values: {
                plan_id: old_plan.broker_provided_id,
                service_id: old_plan.service.broker_provided_id,
                organization_id: instance.organization.guid,
                space_id: instance.space.guid
              }
            }
          )
        end
      end

      context 'when the caller passes the accepts_incomplete flag' do
        let(:path) { "/v2/service_instances/#{instance.guid}?accepts_incomplete=true" }

        it 'adds the flag to the path of the service broker request' do
          client.update_service_plan(instance, new_plan, accepts_incomplete: true)

          expect(http_client).to have_received(:patch).
            with(path, anything)
        end

        context 'and the broker returns last_operation state `succeeded`' do
          let(:response_data) do
            {
              last_operation: {
                state: 'succeeded',
                description: 'finished updating'
              }
            }
          end

          it 'forwards the last operation state from the broker' do
            attributes, _, err = client.update_service_plan(instance, new_plan, accepts_incomplete: true)

            last_operation = attributes[:last_operation]
            expect(err).to be_nil
            expect(last_operation[:type]).to eq('update')
            expect(last_operation[:state]).to eq('succeeded')
            expect(last_operation[:description]).to eq('finished updating')
            expect(last_operation[:proposed_changes]).to be_nil
          end

          it 'returns the new service_plan in a hash' do
            attributes, _, err = client.update_service_plan(instance, new_plan, accepts_incomplete: true)
            expect(err).to be_nil
            expect(attributes[:service_plan]).to eq new_plan
          end
        end

        context 'when the broker does not return a last_operation' do
          let(:response_data) { { bogus_key: 'bogus_value' } }

          it 'defaults the last operation state to `succeeded`' do
            attributes, _, err = client.update_service_plan(instance, new_plan, accepts_incomplete: true)

            last_operation = attributes[:last_operation]
            expect(err).to be_nil
            expect(last_operation[:type]).to eq('update')
            expect(last_operation[:state]).to eq('succeeded')
            expect(last_operation[:description]).to eq('')
            expect(last_operation[:proposed_changes]).to be_nil
          end

          it 'returns the new service_plan in a hash' do
            attributes, _, err = client.update_service_plan(instance, new_plan, accepts_incomplete: true)
            expect(err).to be_nil
            expect(attributes[:service_plan]).to eq new_plan
          end
        end

        context 'when the broker returns the state as `in progress`' do
          let(:code) { 202 }
          let(:message) { 'Accepted' }
          let(:response_data) do
            {
              last_operation: {
                state: 'in progress',
                description: '10% done'
              },
            }
          end

          it 'return immediately with the broker response' do
            client = Client.new(client_attrs.merge(accepts_incomplete: true))
            attributes, _, error = client.update_service_plan(instance, new_plan, accepts_incomplete: true)

            expect(attributes[:last_operation][:type]).to eq('update')
            expect(attributes[:last_operation][:state]).to eq('in progress')
            expect(attributes[:last_operation][:description]).to eq('10% done')
            expect(error).to be_nil
          end

          it 'does not enqueue a job to fetch operation state' do
            expect {
              client.update_service_plan(instance, new_plan, accepts_incomplete: true)
            }.not_to change { Delayed::Job.count }
          end

          it 'returns an interval for polling the operation state' do
            _, polling_interval, _ = client.update_service_plan(instance, new_plan, accepts_incomplete: true)
            expect(polling_interval).to eq(60)
          end

          context 'and async_poll_interval_seconds is set by the broker' do
            let(:broker_polling_interval) { '120' }
            let(:response_data) do
              {
                last_operation: {
                  state: 'in progress',
                  description: '10% done',
                  async_poll_interval_seconds: broker_polling_interval
                },
              }
            end

            it 'parses the value as an integer' do
              _, polling_interval, _ = client.update_service_plan(instance, new_plan, accepts_incomplete: true)
              expect(polling_interval).to eq 120
            end
          end
        end
      end

      describe 'error handling' do
        let(:response_parser) { instance_double(ResponseParser) }
        before do
          allow(ResponseParser).to receive(:new).and_return(response_parser)
        end

        describe 'when the http client raises a ServiceBrokerApiTimeout error' do
          let(:error) { Errors::ServiceBrokerApiTimeout.new('some-uri.com', :patch, nil) }
          before do
            allow(http_client).to receive(:patch).and_raise(error)
          end

          it 'returns no polling_interval' do
            _, polling_interval, _ = client.update_service_plan(instance, new_plan, accepts_incomplete: true)
            expect(polling_interval).to be_nil
          end

          it 'returns an array containing the update attributes and the error' do
            attrs, _, err = client.update_service_plan(instance, new_plan, accepts_incomplete: true)

            expect(err).to eq error
            expect(attrs).to eq({
              last_operation: {
                state: 'failed',
                type: 'update',
                description: error.message,
              }
            })
          end
        end

        describe 'when the response parser raises a ServiceBrokerBadResponse error' do
          let(:response) { instance_double(HttpResponse, code: 500, body: { description: 'BOOOO' }.to_json) }
          let(:error) { Errors::ServiceBrokerBadResponse.new('some-uri.com', :patch, response) }
          before do
            allow(response_parser).to receive(:parse).and_raise(error)
          end

          it 'returns no polling_interval' do
            _, polling_interval, _ = client.update_service_plan(instance, new_plan, accepts_incomplete: true)
            expect(polling_interval).to be_nil
          end

          it 'returns an array containing the update attributes and the error' do
            attrs, _, err = client.update_service_plan(instance, new_plan, accepts_incomplete: true)

            expect(err).to eq error
            expect(attrs).to eq({
              last_operation: {
                state: 'failed',
                type: 'update',
                description: error.message,
              }
            })
          end
        end

        describe 'when the response parser raises a ServiceBrokerResponseMalformed error' do
          let(:response) { instance_double(HttpResponse, code: 200, body: 'some arbitrary body') }
          let(:error) { Errors::ServiceBrokerResponseMalformed.new('some-uri.com', :patch, response, '') }
          before do
            allow(response_parser).to receive(:parse).and_raise(error)
          end

          it 'returns no polling_interval' do
            _, polling_interval, _ = client.update_service_plan(instance, new_plan, accepts_incomplete: true)
            expect(polling_interval).to be_nil
          end

          it 'returns an array containing the update attributes and the error' do
            attrs, _, err = client.update_service_plan(instance, new_plan, accepts_incomplete: true)

            expect(err).to eq error
            expect(attrs).to eq({
              last_operation: {
                state: 'failed',
                type: 'update',
                description: error.message,
              }
            })
          end
        end

        describe 'when the response parser raises a ServiceBrokerRequestRejected error' do
          let(:response) { instance_double(HttpResponse, code: 422, body: { description: 'update not allowed' }.to_json) }
          let(:error) { Errors::ServiceBrokerRequestRejected.new('some-uri.com', :patch, response) }
          before do
            allow(response_parser).to receive(:parse).and_raise(error)
          end

          it 'returns no polling_interval' do
            _, polling_interval, _ = client.update_service_plan(instance, new_plan, accepts_incomplete: true)
            expect(polling_interval).to be_nil
          end

          it 'returns an array containing the update attributes and the error' do
            attrs, _, err = client.update_service_plan(instance, new_plan, accepts_incomplete: 'true')

            expect(err).to eq error
            expect(attrs).to eq({
              last_operation: {
                state: 'failed',
                type: 'update',
                description: error.message,
              }
            })
          end
        end

        describe 'when the response parser raises an AsyncRequired error' do
          let(:response) { instance_double(HttpResponse, code: 422, body: { error: 'AsyncRequired', description: 'update not allowed' }.to_json) }
          let(:error) { Errors::AsyncRequired.new('some-uri.com', :patch, response) }
          before do
            allow(response_parser).to receive(:parse).and_raise(error)
          end

          it 'returns no polling_interval' do
            _, polling_interval, _ = client.update_service_plan(instance, new_plan, accepts_incomplete: true)
            expect(polling_interval).to be_nil
          end

          it 'returns an array containing the update attributes and the error' do
            attrs, _, err = client.update_service_plan(instance, new_plan, accepts_incomplete: 'true')

            expect(err).to eq error
            expect(attrs).to eq({
              last_operation: {
                state: 'failed',
                type: 'update',
                description: error.message,
              }
            })
          end
        end
      end
    end

    describe '#bind' do
      let(:instance) { VCAP::CloudController::ManagedServiceInstance.make }
      let(:app) { VCAP::CloudController::App.make(space: instance.space) }
      let(:binding) do
        VCAP::CloudController::ServiceBinding.new(
          service_instance: instance,
          app: app
        )
      end
      let(:service_key) do
        VCAP::CloudController::ServiceKey.new(
            name: 'fake-service_key',
            service_instance: instance
        )
      end

      let(:response_data) do
        {
          'credentials' => {
            'username' => 'admin',
            'password' => 'secret'
          }
        }
      end

      let(:path) { "/v2/service_instances/#{binding.service_instance.guid}/service_bindings/#{binding.guid}" }
      let(:response) { HttpResponse.new(body: response_body, code: code, message: message) }
      let(:response_body) { response_data.to_json }
      let(:code) { '201' }
      let(:message) { 'Created' }

      before do
        instance.service_plan.service.update_from_hash(requires: ['syslog_drain'])
        allow(http_client).to receive(:put).and_return(response)
      end

      it 'makes a put request with correct path' do
        client.bind(binding)

        expect(http_client).to have_received(:put).
          with("/v2/service_instances/#{binding.service_instance.guid}/service_bindings/#{binding.guid}", anything)
      end

      it 'makes a put request with correct message' do
        client.bind(binding)

        expect(http_client).to have_received(:put).
          with(anything,
             plan_id:    binding.service_plan.broker_provided_id,
             service_id: binding.service.broker_provided_id,
             app_guid:   binding.app_guid
        )
      end

      it 'makes a put request to create a service key with correct message' do
        client.bind(service_key)

        expect(http_client).to have_received(:put).
          with(anything,
              plan_id:    binding.service_plan.broker_provided_id,
              service_id: binding.service.broker_provided_id
        )
      end

      it 'sets the credentials on the binding' do
        attributes = client.bind(binding)
        # ensure attributes return match ones for the database
        binding.set_all(attributes)
        binding.save

        expect(binding.credentials).to eq({
          'username' => 'admin',
          'password' => 'secret'
        })
      end

      context 'with a syslog drain url' do
        let(:response_data) do
          {
            'credentials' => {},
            'syslog_drain_url' => 'syslog://example.com:514'
          }
        end

        it 'sets the syslog_drain_url on the binding' do
          attributes = client.bind(binding)
          # ensure attributes return match ones for the database
          binding.set_all(attributes)
          binding.save

          expect(binding.syslog_drain_url).to eq('syslog://example.com:514')
        end
      end

      context 'without a syslog drain url' do
        let(:response_data) do
          {
            'credentials' => {}
          }
        end

        it 'does not set the syslog_drain_url on the binding' do
          client.bind(binding)
          expect(binding.syslog_drain_url).to_not be
        end
      end

      context 'when binding fails' do
        let(:binding) do
          VCAP::CloudController::ServiceBinding.make(
            binding_options: { 'this' => 'that' }
          )
        end
        let(:uri) { 'some-uri.com/v2/service_instances/instance-guid/service_bindings/binding-guid' }
        let(:response) { HttpResponse.new(body: nil, message: nil, code: nil) }

        context 'due to an http client error' do
          let(:http_client) { instance_double(HttpClient) }

          before do
            allow(http_client).to receive(:put).and_raise(error)
          end

          context 'Errors::ServiceBrokerApiTimeout error' do
            let(:error) { Errors::ServiceBrokerApiTimeout.new(uri, :put, Timeout::Error.new) }

            it 'propagates the error and follows up with a deprovision request' do
              expect {
                client.bind(binding)
              }.to raise_error(Errors::ServiceBrokerApiTimeout)

              expect(orphan_mitigator).to have_received(:cleanup_failed_bind).
                with(client_attrs, binding)
            end
          end
        end

        context 'due to a response parser error' do
          let(:response_parser) { instance_double(ResponseParser) }

          before do
            allow(response_parser).to receive(:parse).and_raise(error)
            allow(VCAP::Services::ServiceBrokers::V2::ResponseParser).to receive(:new).and_return(response_parser)
          end

          context 'Errors::ServiceBrokerApiTimeout error' do
            let(:error) { Errors::ServiceBrokerApiTimeout.new(uri, :put, Timeout::Error.new) }

            it 'propagates the error and follows up with a deprovision request' do
              expect {
                client.bind(binding)
              }.to raise_error(Errors::ServiceBrokerApiTimeout)

              expect(orphan_mitigator).to have_received(:cleanup_failed_bind).with(client_attrs, binding)
            end
          end

          context 'ServiceBrokerBadResponse error' do
            let(:error) { Errors::ServiceBrokerBadResponse.new(uri, :put, response) }

            it 'propagates the error and follows up with a deprovision request' do
              expect {
                client.bind(binding)
              }.to raise_error(Errors::ServiceBrokerBadResponse)

              expect(orphan_mitigator).to have_received(:cleanup_failed_bind).with(client_attrs, binding)
            end
          end
        end
      end
    end

    describe '#unbind' do
      let(:binding) do
        VCAP::CloudController::ServiceBinding.make(
          binding_options: { 'this' => 'that' }
        )
      end

      let(:response_data) { {} }

      let(:path) { "/v2/service_instances/#{binding.service_instance.guid}/service_bindings/#{binding.guid}" }
      let(:response) { HttpResponse.new(code: code, body: response_body, message: message) }
      let(:response_body) { response_data.to_json }
      let(:code) { '200' }
      let(:message) { 'OK' }

      before do
        allow(http_client).to receive(:delete).and_return(response)
      end

      it 'makes a delete request with the correct path' do
        client.unbind(binding)

        expect(http_client).to have_received(:delete).
          with("/v2/service_instances/#{binding.service_instance.guid}/service_bindings/#{binding.guid}", anything)
      end

      it 'makes a delete request with correct message' do
        client.unbind(binding)

        expect(http_client).to have_received(:delete).
          with(anything,
               {
            plan_id:    binding.service_plan.broker_provided_id,
            service_id: binding.service.broker_provided_id,
          }
              )
      end
    end

    describe '#deprovision' do
      let(:instance) { VCAP::CloudController::ManagedServiceInstance.make }

      let(:response_data) { {} }

      let(:path) { "/v2/service_instances/#{instance.guid}" }
      let(:response) { HttpResponse.new(code: code, body: response_body, message: message) }
      let(:response_body) { response_data.to_json }
      let(:code) { '200' }
      let(:message) { 'OK' }

      before do
        allow(http_client).to receive(:delete).and_return(response)
      end

      it 'makes a delete request with the correct path' do
        client.deprovision(instance)

        expect(http_client).to have_received(:delete).
          with("/v2/service_instances/#{instance.guid}", anything)
      end

      it 'makes a delete request with correct message' do
        client.deprovision(instance)

        expect(http_client).to have_received(:delete).with(
            anything,
            {
              service_id: instance.service.broker_provided_id,
              plan_id:    instance.service_plan.broker_provided_id
            }
          )
      end

      context 'when the caller does not pass the accepts_incomplete flag' do
        it 'returns a last_operation hash with a state defaulted to `succeeded`' do
          attrs, _  = client.deprovision(instance)
          expect(attrs).to eq({
            last_operation: {
              type: 'delete',
              state: 'succeeded',
              description: ''
            }
          })
        end

        it 'does not enqueue a job to fetch the state of the instance' do
          expect {
            client.deprovision(instance)
          }.not_to change {
            Delayed::Job.count
          }
        end
      end

      context 'when the caller passes the accepts_incomplete flag' do
        let(:state) { 'succeeded' }
        let(:response_data) do
          {
            last_operation: {
              state: state,
              description: 'working on it'
            }
          }
        end

        it 'adds the flag to the path of the service broker request' do
          client.deprovision(instance, accepts_incomplete: true)

          expect(http_client).to have_received(:delete).
            with(path, hash_including(accepts_incomplete: true))
        end

        context 'when the last_operation state is `in progress`' do
          let(:code) { 202 }
          let(:state) { 'in progress' }

          it 'returns the last_operation hash' do
            attrs, _ = client.deprovision(instance, accepts_incomplete: true)
            expect(attrs).to eq({
              last_operation: {
                type: 'delete',
                state: state,
                description: 'working on it'
              }
            })
          end

          it 'does not enqueue a job to fetch operation state' do
            expect {
              client.deprovision(instance, accepts_incomplete: true)
            }.not_to change { Delayed::Job.count }
          end

          context 'and async_poll_interval_seconds is set by the broker' do
            let(:poll_interval) { '500' }
            let(:response_data) do
              {
                last_operation: {
                  state: 'in progress',
                  description: '10% done',
                  async_poll_interval_seconds: poll_interval
                },
              }
            end

            it 'parses the value as an integer' do
              _, polling_interval = client.deprovision(instance, accepts_incomplete: true)
              expect(polling_interval).to eq 500
            end
          end
        end

        context 'when the last_operation state is `succeeded`' do
          let(:code) { 200 }
          let(:state) { 'succeeded' }

          it 'returns the last_operation hash' do
            attrs, _ = client.deprovision(instance, accepts_incomplete: true)
            expect(attrs).to eq({
              last_operation: {
                type: 'delete',
                state: 'succeeded',
                description: 'working on it'
              }
            })
          end

          it 'does not enqueue a job to fetch the state of the instance' do
            expect {
              client.deprovision(instance, accepts_incomplete: true)
            }.not_to change {
              Delayed::Job.count
            }
          end

          it 'returns no polling_interval' do
            _, polling_interval, _ = client.deprovision(instance, accepts_incomplete: true)
            expect(polling_interval).to be_nil
          end
        end

        context 'when the last_operation is not included' do
          let(:code) { 200 }
          let(:response_data) { {} }

          it 'returns a last_operation hash that has state defaulted to `succeeded`' do
            attrs, _ = client.deprovision(instance, accepts_incomplete: true)
            expect(attrs).to eq({
              last_operation: {
                type: 'delete',
                state: 'succeeded',
                description: ''
              }
            })
          end

          it 'does not enqueue a job to fetch the state of the instance' do
            expect {
              client.deprovision(instance, accepts_incomplete: true)
            }.not_to change {
              Delayed::Job.count
            }
          end

          it 'returns no polling_interval' do
            _, polling_interval, _ = client.deprovision(instance, accepts_incomplete: true)
            expect(polling_interval).to be_nil
          end
        end
      end
    end

    def unwrap_delayed_job(job)
      job.payload_object.handler.handler.handler
    end
  end
end
