require 'spec_helper'

module VCAP::CloudController
  describe ManagedServiceInstance, type: :model do
    let(:service_instance) { VCAP::CloudController::ManagedServiceInstance.make }
    let(:email) { Sham.email }
    let(:guid) { Sham.guid }

    after { VCAP::Request.current_id = nil }

    before do
      allow(VCAP::CloudController::SecurityContext).to receive(:current_user_email) { email }

      client = instance_double(VCAP::Services::ServiceBrokers::V2::Client, unbind: nil, deprovision: nil)
      allow_any_instance_of(Service).to receive(:client).and_return(client)
    end

    it { is_expected.to have_timestamp_columns }

    describe 'Associations' do
      it { is_expected.to have_associated :service_plan }
      it { is_expected.to have_associated :space }
      it do
        is_expected.to have_associated :service_bindings, associated_instance: ->(service_instance) {
          app = VCAP::CloudController::App.make(space: service_instance.space)
          ServiceBinding.make(app: app, service_instance: service_instance, credentials: Sham.service_credentials)
        }
      end
    end

    describe 'Validations' do
      it { is_expected.to validate_presence :name }
      it { is_expected.to validate_presence :service_plan }
      it { is_expected.to validate_presence :space }
      it { is_expected.to validate_uniqueness [:space_id, :name] }
      it { is_expected.to strip_whitespace :name }

      it 'should not bind an app and a service instance from different app spaces' do
        AppFactory.make(space: service_instance.space)
        service_binding = ServiceBinding.make
        expect {
          service_instance.add_service_binding(service_binding)
        }.to raise_error ServiceInstance::InvalidServiceBinding
      end

      it 'validates org and space quotas using MaxServiceInstancePolicy' do
        space_quota_definition = SpaceQuotaDefinition.make
        service_instance.space.space_quota_definition = space_quota_definition
        max_memory_policies = service_instance.validation_policies.select { |policy| policy.instance_of? MaxServiceInstancePolicy }
        expect(max_memory_policies.length).to eq(2)
        targets = max_memory_policies.collect(&:quota_definition)
        expect(targets).to match_array([space_quota_definition, service_instance.organization.quota_definition])
      end

      it 'validates org and space quotas using PaidServiceInstancePolicy' do
        space_quota_definition = SpaceQuotaDefinition.make
        service_instance.space.space_quota_definition = space_quota_definition
        policies = service_instance.validation_policies.select { |policy| policy.instance_of? PaidServiceInstancePolicy }
        expect(policies.length).to eq(2)
        targets = policies.collect(&:quota_definition)
        expect(targets).to match_array([space_quota_definition, service_instance.organization.quota_definition])
      end
    end

    describe 'Serialization' do
      it { is_expected.to export_attributes :name, :credentials, :service_plan_guid, :space_guid, :gateway_data, :dashboard_url, :type, :last_operation }
      it { is_expected.to import_attributes :name, :service_plan_guid, :space_guid, :gateway_data }
    end

    describe '#create' do
      it 'has a guid when constructed' do
        instance = described_class.new
        expect(instance.guid).to be
      end

      it 'saves with is_gateway_service true' do
        instance = described_class.make
        expect(instance.refresh.is_gateway_service).to eq(true)
      end

      it 'creates a CREATED service usage event' do
        instance = described_class.make

        event = ServiceUsageEvent.last
        expect(ServiceUsageEvent.count).to eq(1)
        expect(event.state).to eq(Repositories::Services::ServiceUsageEventRepository::CREATED_EVENT_STATE)
        expect(event).to match_service_instance(instance)
      end
    end

    describe '#lock_by_blocking_other_operations' do
      it 'locks the service instance' do
        allow(service_instance).to receive(:lock!).and_call_original

        service_instance.lock_by_blocking_other_operations {}

        expect(service_instance).to have_received(:lock!)
      end

      context 'when the instance has a last_operation' do
        let(:last_operation) { ServiceInstanceOperation.make(state: 'succeeded') }
        before do
          allow(service_instance).to receive(:last_operation).and_return(last_operation)
        end

        it 'locks the last_operation' do
          allow(last_operation).to receive(:lock!).and_call_original

          service_instance.lock_by_blocking_other_operations {}

          expect(last_operation).to have_received(:lock!)
        end
      end

      context 'when there is an operation in progress' do
        before do
          service_instance.save_with_operation({
            last_operation: {
              state: 'in progress'
            }
          })
        end

        it 'raises an error' do
          expect {
            service_instance.lock_by_blocking_other_operations {}
          }.to raise_error(Errors::ApiError)
        end
      end
    end

    describe '#lock_by_failing_other_operations' do
      it 'locks the service instance' do
        allow(service_instance).to receive(:lock!).and_call_original

        service_instance.lock_by_failing_other_operations('update') {}

        expect(service_instance).to have_received(:lock!).twice
      end

      context 'when the instance has a last_operation' do
        let(:last_operation) { ServiceInstanceOperation.make(state: 'succeeded') }
        before do
          allow(service_instance).to receive(:last_operation).and_return(last_operation)
        end

        it 'locks the last_operation' do
          allow(last_operation).to receive(:lock!).and_call_original

          service_instance.lock_by_failing_other_operations('update') {}

          expect(last_operation).to have_received(:lock!)
        end
      end

      it 'initially saves the last_operation state as `in progress`' do
        service_instance.lock_by_failing_other_operations('update') {}

        service_instance.reload.last_operation.reload
        expect(service_instance.last_operation.type).to eq 'update'
        expect(service_instance.last_operation.state).to eq 'in progress'
      end

      context 'when there is an operation in progress' do
        before do
          service_instance.save_with_operation({
            last_operation: {
              state: 'in progress'
            }
          })
        end

        it 'raises an error' do
          expect {
            service_instance.lock_by_failing_other_operations('update') {}
          }.to raise_error(Errors::ApiError)
        end
      end

      context 'when the block fails' do
        it 'updates the last_operation to state `failed`' do
          expect {
            service_instance.lock_by_failing_other_operations('update') { raise 'BOOO' }
          }.to raise_error(StandardError, /BOOO/)

          service_instance.reload.last_operation.reload
          expect(service_instance.last_operation.type).to eq 'update'
          expect(service_instance.last_operation.state).to eq 'failed'
        end
      end
    end

    describe '#save_with_operation' do
      context 'when the operation does not exist' do
        it 'also creates a last_operation object and assoicates it with the service instance' do
          service_instance = ManagedServiceInstance.make
          attrs = {
            last_operation: {
              state: 'in progress',
              description: '10%'
            },
            dashboard_url: 'a-different-url.com'
          }
          service_instance.save_with_operation(attrs)

          service_instance.reload
          expect(service_instance.dashboard_url).to eq 'a-different-url.com'
          expect(service_instance.last_operation.state).to eq 'in progress'
          expect(service_instance.last_operation.description).to eq '10%'
        end
      end

      context 'when the operation already exists' do
        it 'updates the existing operation associated with the service instance' do
          operation = ServiceInstanceOperation.make
          service_instance = ManagedServiceInstance.make
          service_instance.service_instance_operation = operation
          attrs = {
            last_operation: {
              state: 'in progress',
              description: '10%'
            },
            dashboard_url: 'a-different-url.com'
          }
          service_instance.save_with_operation(attrs)

          service_instance.reload
          expect(service_instance.dashboard_url).to eq 'a-different-url.com'
          expect(service_instance.last_operation.state).to eq 'in progress'
          expect(service_instance.last_operation.description).to eq '10%'
        end
      end
    end

    describe '#delete' do
      it 'creates a DELETED service usage event' do
        instance = described_class.make
        instance.destroy

        event = VCAP::CloudController::ServiceUsageEvent.last

        expect(VCAP::CloudController::ServiceUsageEvent.count).to eq(2)
        expect(event.state).to eq(Repositories::Services::ServiceUsageEventRepository::DELETED_EVENT_STATE)
        expect(event).to match_service_instance(instance)
      end

      it 'cascade deletes all ServiceInstanceOperations for this instance' do
        last_operation = ServiceInstanceOperation.make
        service_instance.service_instance_operation = last_operation

        service_instance.destroy

        expect(ServiceInstance.find(guid: service_instance.guid)).to be_nil
        expect(ServiceInstanceOperation.find(guid: last_operation.guid)).to be_nil
      end
    end

    describe 'lifecycle' do
      context 'service deprovisioning' do
        it 'should deprovision a service on destroy' do
          expect(service_instance.client).to receive(:deprovision).with(service_instance)
          service_instance.destroy
        end
      end

      context 'when deprovision fails' do
        it 'should raise and rollback' do
          allow(service_instance.client).to receive(:deprovision).and_raise
          expect {
            service_instance.destroy
          }.to raise_error
          expect(VCAP::CloudController::ManagedServiceInstance.find(id: service_instance.id)).to be
        end
      end
    end

    context 'billing' do
      context 'creating a service instance' do
        it 'should call ServiceCreateEvent.create_from_service_instance' do
          expect(ServiceCreateEvent).to receive(:create_from_service_instance)
          expect(ServiceDeleteEvent).not_to receive(:create_from_service_instance)
          service_instance
        end
      end

      context 'destroying a service instance' do
        it 'should call ServiceDeleteEvent.create_from_service_instance' do
          service_instance
          expect(ServiceCreateEvent).not_to receive(:create_from_service_instance)
          expect(ServiceDeleteEvent).to receive(:create_from_service_instance).with(service_instance)
          service_instance.destroy
        end
      end
    end

    describe '#as_summary_json' do
      let(:service) { Service.make(label: 'YourSQL', guid: '9876XZ', provider: 'Bill Gates', version: '1.2.3') }
      let(:service_plan) { ServicePlan.make(name: 'Gold Plan', guid: '12763abc', service: service) }
      subject(:service_instance) { ManagedServiceInstance.make(service_plan: service_plan) }

      it 'returns detailed summary' do
        updated_at_time = Time.now.utc
        last_operation = ServiceInstanceOperation.make(
          state: 'in progress',
          description: '50% all the time',
          type: 'create',
          updated_at: updated_at_time
        )
        service_instance.service_instance_operation = last_operation

        service_instance.dashboard_url = 'http://dashboard.example.com'

        expect(service_instance.as_summary_json).to include({
          'guid' => subject.guid,
          'name' => subject.name,
          'bound_app_count' => 0,
          'dashboard_url' => 'http://dashboard.example.com',
          'service_plan' => {
            'guid' => '12763abc',
            'name' => 'Gold Plan',
            'service' => {
              'guid' => '9876XZ',
              'label' => 'YourSQL',
              'provider' => 'Bill Gates',
              'version' => '1.2.3',
            }
          }
        })

        expect(service_instance.as_summary_json['last_operation']).to include(
          {
            'state' => 'in progress',
            'description' => '50% all the time',
            'type' => 'create',
          }
        )

        expect(service_instance.as_summary_json['last_operation']['updated_at']).to be_within(1.second).of updated_at_time
      end

      context 'when the last_operation does not exist' do
        it 'sets the field to nil' do
          expect(service_instance.as_summary_json['last_operation']).to be_nil
        end
      end
    end

    context 'quota' do
      let(:free_plan) { ServicePlan.make(free: true) }
      let(:paid_plan) { ServicePlan.make(free: false) }

      let(:free_quota) do
        QuotaDefinition.make(
          total_services: 1,
          non_basic_services_allowed: false
        )
      end
      let(:paid_quota) do
        QuotaDefinition.make(
          total_services: 1,
          non_basic_services_allowed: true
        )
      end

      context 'exceed quota' do
        it 'should raise quota error when quota is exceeded' do
          org = Organization.make(quota_definition: free_quota)
          space = Space.make(organization: org)
          ManagedServiceInstance.make(
            space: space,
            service_plan: free_plan
          ).save(validate: false)
          space.refresh
          expect do
            ManagedServiceInstance.make(
              space: space,
              service_plan: free_plan
            )
          end.to raise_error(Sequel::ValidationFailed, /quota service_instance_quota_exceeded/)
        end

        it 'should not raise error when quota is not exceeded' do
          org = Organization.make(quota_definition: paid_quota)
          space = Space.make(organization: org)
          expect do
            ManagedServiceInstance.make(
              space: space,
              service_plan: free_plan
            )
          end.to_not raise_error
        end
      end

      context 'create free services' do
        it 'should not raise error when created in free quota' do
          org = Organization.make(quota_definition: free_quota)
          space = Space.make(organization: org)
          expect do
            ManagedServiceInstance.make(
              space: space,
              service_plan: free_plan
            )
          end.to_not raise_error
        end

        it 'should not raise error when created in paid quota' do
          org = Organization.make(quota_definition: paid_quota)
          space = Space.make(organization: org)
          expect do
            ManagedServiceInstance.make(
              space: space,
              service_plan: free_plan
            )
          end.to_not raise_error
        end
      end

      context 'create paid services' do
        it 'should raise error when created in free quota' do
          org = Organization.make(quota_definition: free_quota)
          space = Space.make(organization: org)
          expect do
            ManagedServiceInstance.make(
              space: space,
              service_plan: paid_plan
            )
          end.to raise_error(Sequel::ValidationFailed,
                             /service_plan paid_services_not_allowed_by_quota/)
        end

        it 'should not raise error when created in paid quota' do
          org = Organization.make(quota_definition: paid_quota)
          space = Space.make(organization: org)
          expect do
            ManagedServiceInstance.make(
              space: space,
              service_plan: paid_plan
            )
          end.to_not raise_error
        end
      end
    end

    describe '#destroy' do
      subject { service_instance.destroy }

      it 'destroys the service bindings' do
        service_binding = ServiceBinding.make(
          app: AppFactory.make(space: service_instance.space),
          service_instance: service_instance
        )
        expect { subject }.to change { ServiceBinding.where(id: service_binding.id).count }.by(-1)
      end
    end

    describe '#enum_snapshots' do
      subject { ManagedServiceInstance.make(:v1) }
      let(:enum_snapshots_url_matcher) { "gw.example.com:12345/gateway/v2/configurations/#{subject.gateway_name}/snapshots" }
      let(:service_auth_token) { 'tokenvalue' }
      before do
        subject.service_plan.service.update(url: 'http://gw.example.com:12345/')
        subject.service_plan.service.service_auth_token.update(token: service_auth_token)
      end

      context "when there isn't a service auth token" do
        it 'fails' do
          subject.service_plan.service.service_auth_token.destroy
          subject.refresh
          expect do
            subject.enum_snapshots
          end.to raise_error(VCAP::Errors::ApiError, /Missing service auth token/)
        end
      end

      context 'returns a list of snapshots' do
        let(:success_response) { MultiJson.dump({ snapshots: [{ snapshot_id: '1', name: 'foo', state: 'ok', size: 0 },
                                                              { snapshot_id: '2', name: 'bar', state: 'bad', size: 0 }] })
        }
        before do
          stub_request(:get, enum_snapshots_url_matcher).to_return(body: success_response)
        end

        it 'return a list of snapshot from the gateway' do
          snapshots = subject.enum_snapshots
          expect(snapshots).to have(2).items
          expect(snapshots.first.snapshot_id).to eq('1')
          expect(snapshots.first.state).to eq('ok')
          expect(snapshots.last.snapshot_id).to eq('2')
          expect(snapshots.last.state).to eq('bad')
          expect(a_request(:get, enum_snapshots_url_matcher).with(headers: {
            'Content-Type' => 'application/json',
            'X-Vcap-Service-Token' => 'tokenvalue'
          })).to have_been_made
        end
      end
    end

    describe '#create_snapshot' do
      let(:name) { 'New snapshot' }
      subject { ManagedServiceInstance.make(:v1) }
      let(:create_snapshot_url_matcher) { "gw.example.com:12345/gateway/v2/configurations/#{subject.gateway_name}/snapshots" }
      before do
        subject.service_plan.service.update(url: 'http://gw.example.com:12345/')
        subject.service_plan.service.service_auth_token.update(token: 'tokenvalue')
      end

      context "when there isn't a service auth token" do
        it 'fails' do
          subject.service_plan.service.service_auth_token.destroy
          subject.refresh
          expect do
            subject.create_snapshot(name)
          end.to raise_error(VCAP::Errors::ApiError, /Missing service auth token/)
        end
      end

      it 'rejects empty string as name' do
        expect do
          subject.create_snapshot('')
        end.to raise_error(JsonMessage::ValidationError, /Field: name/)
      end

      context 'when the request succeeds' do
        let(:success_response) { %({"snapshot_id": "1", "state": "empty", "name": "foo", "size": 0}) }
        before do
          stub_request(:post, create_snapshot_url_matcher).to_return(body: success_response)
        end

        it 'makes an HTTP call to the corresponding service gateway and returns the decoded response' do
          snapshot = subject.create_snapshot(name)
          expect(snapshot.snapshot_id).to eq('1')
          expect(snapshot.state).to eq('empty')
          expect(a_request(:post, create_snapshot_url_matcher)).to have_been_made
        end

        it 'uses the correct svc auth token' do
          subject.create_snapshot(name)

          expect(a_request(:post, create_snapshot_url_matcher).with(
            headers: { 'X-VCAP-Service-Token' => 'tokenvalue' })).to have_been_made
        end

        it 'has the name in the payload' do
          payload = MultiJson.dump({ name: name })
          subject.create_snapshot(name)

          expect(a_request(:post, create_snapshot_url_matcher).with(body: payload)).to have_been_made
        end
      end

      context 'when the request fails' do
        it 'should raise an error' do
          stub_request(:post, create_snapshot_url_matcher).to_return(body: 'Something went wrong', status: 500)
          expect { subject.create_snapshot(name) }.to raise_error(ManagedServiceInstance::ServiceGatewayError, /upstream failure/)
        end
      end
    end

    describe '#bindable?' do
      let(:service_instance) { ManagedServiceInstance.make(service_plan: service_plan) }
      let(:service_plan) { ServicePlan.make(service: service) }

      context 'when the service is bindable' do
        let(:service) { Service.make(bindable: true) }

        specify { expect(service_instance).to be_bindable }
      end

      context 'when the service is not bindable' do
        let(:service) { Service.make(bindable: false) }

        specify { expect(service_instance).not_to be_bindable }
      end
    end

    describe '#tags' do
      let(:service_instance) { ManagedServiceInstance.make(service_plan: service_plan) }
      let(:service_plan) { ServicePlan.make(service: service) }
      let(:service) { Service.make(tags: %w(relational mysql)) }

      it 'gets tags from the service' do
        expect(service_instance.tags).to eq %w(relational mysql)
      end
    end

    describe '#terminal_state?' do
      def build_instance_with_op_state(state)
        last_operation = ServiceInstanceOperation.make(state: state)
        instance = ManagedServiceInstance.make
        instance.service_instance_operation = last_operation
        instance
      end

      it 'returns true when state is `succeeded`' do
        instance = build_instance_with_op_state('succeeded')
        expect(instance.terminal_state?).to be true
      end

      it 'returns true when state is `failed`' do
        instance = build_instance_with_op_state('failed')
        expect(instance.terminal_state?).to be true
      end

      it 'returns false otherwise' do
        instance = build_instance_with_op_state('other')
        expect(instance.terminal_state?).to be false
      end
    end

    describe '#operation_in_progress?' do
      let(:service_instance) { ManagedServiceInstance.make }
      before do
        service_instance.service_instance_operation = last_operation
        service_instance.save
      end

      context 'when the last operation is `in progress`' do
        let(:last_operation) { ServiceInstanceOperation.make(state: 'in progress') }
        it 'returns true' do
          expect(service_instance.operation_in_progress?).to eq true
        end
      end

      context 'when the last operation is succeeded' do
        let(:last_operation) { ServiceInstanceOperation.make(state: 'succeeded') }
        it 'returns false' do
          expect(service_instance.operation_in_progress?).to eq false
        end
      end

      context 'when the last operation is failed' do
        let(:last_operation) { ServiceInstanceOperation.make(state: 'failed') }
        it 'returns false' do
          expect(service_instance.operation_in_progress?).to eq false
        end
      end

      context 'when the last operation is nil' do
        let(:last_operation) { nil }
        it 'returns false' do
          expect(service_instance.operation_in_progress?).to eq false
        end
      end
    end

    describe '#to_hash' do
      let(:opts)            { { attrs: [:credentials] } }
      let(:developer)       { make_developer_for_space(service_instance.space) }
      let(:auditor)         { make_auditor_for_space(service_instance.space) }
      let(:user)            { make_user_for_space(service_instance.space) }

      it 'includes the last operation hash' do
        updated_at_time = Time.now.utc
        last_operation = ServiceInstanceOperation.make(
          state: 'in progress',
          description: '50% all the time',
          type: 'create',
          updated_at: updated_at_time
        )

        service_instance.service_instance_operation = last_operation
        expect(service_instance.to_hash['last_operation']).to include({
          'state' => 'in progress',
          'description' => '50% all the time',
          'type' => 'create',
        })

        expect(service_instance.to_hash['last_operation']['updated_at']).to be
      end
    end
  end
end
