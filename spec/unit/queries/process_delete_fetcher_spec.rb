require 'spec_helper'
require 'queries/process_delete_fetcher'

module VCAP::CloudController
  describe ProcessDeleteFetcher do
    describe '#fetch' do
      let(:space) { Space.make }
      let(:app_model) { AppModel.make(space_guid: space.guid) }
      let!(:process) { AppFactory.make(app_guid: app_model.guid) }
      let(:user) { User.make(admin: admin) }
      let(:admin) { false }

      subject(:process_delete_fetcher) { ProcessDeleteFetcher.new(user) }

      context 'when the user is an admin' do
        let(:admin) { true }

        it 'returns the process and the space' do
          process_dataset, actual_space = process_delete_fetcher.fetch(process.guid)
          expect(process_dataset).to include(process)
          expect(actual_space).to eq(space)
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
          expect(process_delete_fetcher.fetch(process.guid)).to be_nil
        end
      end

      context 'when the user is a space developer' do
        before do
          space.organization.add_user(user)
          space.add_developer(user)
        end

        it 'returns the process, nothing else' do
          process_dataset, actual_space = process_delete_fetcher.fetch(process.guid)
          expect(process_dataset).to include(process)
          expect(actual_space).to eq(space)
        end
      end

      context 'when the user does not have access to deleting processes' do
        it 'returns nothing' do
          expect(process_delete_fetcher.fetch(process.guid)).to be_nil
        end
      end
    end
  end
end
