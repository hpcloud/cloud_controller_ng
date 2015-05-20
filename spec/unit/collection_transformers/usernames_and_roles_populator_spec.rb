require 'spec_helper'

module VCAP::CloudController
  describe UsernamesAndRolesPopulator do
    let(:uaa_client) { double(UaaClient) }
    let(:username_populator) { UsernamesAndRolesPopulator.new(uaa_client) }
    let(:user1) { User.new(guid: '1') }
    let(:user2) { User.new(guid: '2') }
    let(:users) { [user1, user2] }
    let(:org) { Organization.make }

    before do
      allow(uaa_client).to receive(:usernames_for_ids).with(['1', '2']).and_return({
        '1' => 'Username1',
        '2' => 'Username2'
      })

      org.add_user(user1)
      org.add_auditor(user1)
      org.add_manager(user2)
    end

    describe 'transform' do
      it 'populates users with usernames from UAA' do
        username_populator.transform(users, organization_id: org.id)
        expect(user1.username).to eq('Username1')
        expect(user2.username).to eq('Username2')
      end

      it 'populates users with organization roles' do
        username_populator.transform(users, organization_id: org.id)
        expect(user1.organization_roles).to include('org_user', 'org_auditor')
        expect(user2.organization_roles).to eq(['org_manager'])
      end
    end
  end
end
