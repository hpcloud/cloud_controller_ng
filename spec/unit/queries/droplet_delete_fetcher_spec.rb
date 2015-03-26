require 'spec_helper'
require 'queries/droplet_delete_fetcher'

module VCAP::CloudController
  describe DropletDeleteFetcher do
    describe '#fetch' do
      let(:space) { Space.make }
      let(:app_model) { AppModel.make(space_guid: space.guid) }
      let!(:droplet) { DropletModel.make(app_guid: app_model.guid) }
      let!(:other_droplet) { DropletModel.make(app_guid: app_model.guid) }
      let(:user) { User.make(admin: admin) }
      let(:admin) { false }

      subject(:droplet_delete_fetcher) { DropletDeleteFetcher.new(user) }

      context 'when the user is an admin' do
        let(:admin) { true }

        it 'returns the droplet, nothing else' do
          expect(droplet_delete_fetcher.fetch(droplet.guid)).to include(droplet)
        end
      end

      context 'when the organization is not active' do
        before do
          space.organization.add_user(user)
          space.add_developer(user)
          space.organization.status = 'suspended'
          space.organization.save
        end

        it 'returns nil' do
          expect(droplet_delete_fetcher.fetch(droplet.guid)).to be_empty
        end
      end

      context 'when the user is a space developer' do
        before do
          space.organization.add_user(user)
          space.add_developer(user)
        end

        it 'returns the droplet, nothing else' do
          expect(droplet_delete_fetcher.fetch(droplet.guid)).to include(droplet)
        end
      end

      context 'when the user does not have access to deleting droplets' do
        it 'returns nothing' do
          expect(droplet_delete_fetcher.fetch(droplet.guid)).to be_empty
        end
      end
    end
  end
end
