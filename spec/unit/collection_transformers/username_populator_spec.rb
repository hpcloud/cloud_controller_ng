require 'spec_helper'

module VCAP::CloudController
  describe UsernamePopulator do
    let(:uaa_client) { double(UaaClient) }
    let(:username_populator) { UsernamePopulator.new(uaa_client) }
    let(:user1) { User.new(guid: '1') }
    let(:user2) { User.new(guid: '2') }
    let(:users) { [user1, user2] }

    before do
      allow(uaa_client).to receive(:usernames_for_ids).with(['1', '2']).and_return({
        '1' => 'Username1',
        '2' => 'Username2'
      })
    end

    describe 'transform' do
      it 'populates users with usernames from UAA' do
        pending("STACKATO: This should pass once we move from AOK to UAA")
        username_populator.transform(users)
        expect(user1.username).to eq('Username1')
        expect(user2.username).to eq('Username2')
      end
      it 'echoes user objects with usernames from UAA' do
        # STACKATO: Remove this once we move from AOK to UAA
        user1.username = 'Username1'
        user2.username = 'Username2'
        username_populator.transform(users)
        expect(user1.username).to eq('Username1')
        expect(user2.username).to eq('Username2')
      end
    end
  end
end
