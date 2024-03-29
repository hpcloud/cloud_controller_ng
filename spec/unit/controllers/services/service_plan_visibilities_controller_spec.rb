require 'spec_helper'

module VCAP::CloudController
  describe ServicePlanVisibilitiesController, :services do
    describe 'Attributes' do
      it do
        expect(described_class).to have_creatable_attributes({
          service_plan_guid: { type: 'string', required: true },
          organization_guid: { type: 'string', required: true }
        })
      end

      it do
        expect(described_class).to have_updatable_attributes({
          service_plan_guid: { type: 'string' },
          organization_guid: { type: 'string' }
        })
      end
    end

    describe 'Permissions' do
      include_context 'permissions'

      before do
        @obj_a = ServicePlanVisibility.make
        @obj_b = ServicePlanVisibility.make
      end

      def self.user_sees_empty_enumerate(user_role, member_a_ivar, member_b_ivar)
        describe user_role do
          let(:member_a) { instance_variable_get(member_a_ivar) }
          let(:member_b) { instance_variable_get(member_b_ivar) }

          include_examples 'permission enumeration', user_role,
                           name: 'service plan visibility',
                           path: '/v2/service_plan_visibilities',
                           enumerate: 0
        end
      end

      user_sees_empty_enumerate('Developer',      :@space_a_developer,     :@space_b_developer)
      user_sees_empty_enumerate('OrgManager',     :@org_a_manager,         :@org_b_manager)
      user_sees_empty_enumerate('OrgUser',        :@org_a_member,          :@org_b_member)
      user_sees_empty_enumerate('BillingManager', :@org_a_billing_manager, :@org_b_billing_manager)
      user_sees_empty_enumerate('Auditor',        :@org_a_auditor,         :@org_b_auditor)
      user_sees_empty_enumerate('SpaceManager',   :@space_a_manager,       :@space_b_manager)
      user_sees_empty_enumerate('SpaceAuditor',   :@space_a_auditor,       :@space_b_auditor)
    end

    describe 'Query Parameters' do
      it { expect(described_class).to be_queryable_by(:organization_guid) }
      it { expect(described_class).to be_queryable_by(:service_plan_guid) }
    end

    describe 'POST /v2/service_plan_visibilities' do
      let(:headers) { json_headers(admin_headers) }
      let!(:organization) { Organization.make }
      let!(:service_plan) { ServicePlan.make }

      it 'creates the service plan visibility' do
        params = { organization_guid: organization.guid, service_plan_guid: service_plan.guid }
        post '/v2/service_plan_visibilities', MultiJson.dump(params), headers

        expect(last_response.status).to eq 201

        visibility = ServicePlanVisibility.first
        expect(visibility).to be
        expect(visibility.organization_guid).to eq organization.guid
        expect(visibility.service_plan_guid).to eq service_plan.guid
      end

      it "creates an 'audit.service_plan_visibility.create' event" do
        email = 'some-email-address@example.com'
        params = { 'organization_guid' => organization.guid, 'service_plan_guid' => service_plan.guid }
        post '/v2/service_plan_visibilities', MultiJson.dump(params), headers_for(admin_user, email: email)

        event = Event.first(type: 'audit.service_plan_visibility.create')
        visibility = ServicePlanVisibility.first
        expect(visibility).to be
        expect(event.actor_type).to eq('user')
        expect(event.timestamp).to be
        expect(event.actor).to eq(admin_user.guid)
        expect(event.actor_name).to eq(email)
        expect(event.actee).to eq(visibility.guid)
        expect(event.actee_type).to eq('service_plan_visibility')
        expect(event.actee_name).to eq('')
        expect(event.space_guid).to be_empty
        expect(event.organization_guid).to eq(organization.guid)
        expect(event.metadata).to eq({ 'request' => params })
      end
    end

    describe 'PUT /v2/service_plan_visibilities/:guid' do
      let(:headers) { json_headers(admin_headers) }
      let!(:organization) { Organization.make }
      let!(:new_organization) { Organization.make }
      let!(:service_plan) { ServicePlan.make }
      let!(:visibility) { ServicePlanVisibility.make(organization_guid: organization.guid, service_plan_guid: service_plan.guid) }

      it 'updates the service plan visibility' do
        put "/v2/service_plan_visibilities/#{visibility.guid}", MultiJson.dump({ organization_guid: new_organization.guid }), headers

        expect(last_response.status).to eq(201)
        service_plan_visibility = ServicePlanVisibility.find(guid: visibility.guid)
        expect(service_plan_visibility.organization_guid).to eq new_organization.guid
      end

      it 'creates a service plan visibility update event' do
        email = 'some-email-address@example.com'
        params = { 'organization_guid' => new_organization.guid }
        put "/v2/service_plan_visibilities/#{visibility.guid}", MultiJson.dump(params), headers_for(admin_user, email: email)

        event = Event.first(type: 'audit.service_plan_visibility.update')
        expect(event.actor_type).to eq('user')
        expect(event.timestamp).to be
        expect(event.actor).to eq(admin_user.guid)
        expect(event.actor_name).to eq(email)
        expect(event.actee).to eq(visibility.guid)
        expect(event.actee_type).to eq('service_plan_visibility')
        expect(event.actee_name).to eq('')
        expect(event.space_guid).to be_empty
        expect(event.organization_guid).to eq(new_organization.guid)
        expect(event.metadata).to eq({ 'request' => params })
      end
    end

    describe 'DELETE /v2/service_plan_visibilities/:guid' do
      let(:headers) { json_headers(admin_headers) }
      let!(:organization) { Organization.make }
      let!(:service_plan) { ServicePlan.make }
      let!(:visibility) { ServicePlanVisibility.make(organization_guid: organization.guid, service_plan_guid: service_plan.guid) }

      it 'deletes the service plan visibility' do
        delete "/v2/service_plan_visibilities/#{visibility.guid}", {}, headers

        expect(last_response.status).to eq(204)
        expect(ServicePlanVisibility.find(guid: visibility.guid)).to be_nil
      end

      it 'creates a service plan visibility delete event' do
        email = 'some-email-address@example.com'
        delete "/v2/service_plan_visibilities/#{visibility.guid}", {}, headers_for(admin_user, email: email)

        event = Event.first(type: 'audit.service_plan_visibility.delete')
        expect(event.actor_type).to eq('user')
        expect(event.timestamp).to be
        expect(event.actor).to eq(admin_user.guid)
        expect(event.actor_name).to eq(email)
        expect(event.actee).to eq(visibility.guid)
        expect(event.actee_type).to eq('service_plan_visibility')
        expect(event.actee_name).to eq('')
        expect(event.space_guid).to be_empty
        expect(event.organization_guid).to eq(organization.guid)
        expect(event.metadata).to eq('request' => {})
      end

      context 'with ?async=true' do
        it 'returns a job id' do
          require 'support/stackato_yaml_override'
          delete "/v2/service_plan_visibilities/#{visibility.guid}?async=true", {}, headers
          expect(last_response.status).to eq 202
          expect(decoded_response['entity']['guid']).to be
          expect(decoded_response['entity']['status']).to eq 'queued'

          successes, failures = Delayed::Worker.new.work_off
          expect(successes).to eq 1
          expect(failures).to eq 0

          event = Event.first(type: 'audit.service_plan_visibility.delete')
          expect(event).to be
          expect(ServicePlanVisibility.find(guid: visibility.guid)).to be_nil
        end
      end
    end
  end
end
