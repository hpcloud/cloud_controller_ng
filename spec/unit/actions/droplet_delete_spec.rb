require 'spec_helper'
require 'actions/droplet_delete'

module VCAP::CloudController
  describe DropletDelete do
    subject(:droplet_delete) { DropletDelete.new }

    describe '#delete' do
      context 'when the droplet exists' do
        let!(:droplet) { DropletModel.make(droplet_hash: 'droplet_hash') }
        let!(:droplet_dataset) { DropletModel.where(guid: droplet.guid) }

        it 'deletes the droplet record' do
          expect {
            droplet_delete.delete(droplet_dataset)
          }.to change { DropletModel.count }.by(-1)
          expect { droplet.refresh }.to raise_error Sequel::Error, 'Record not found'
        end

        it 'schedules a job to the delete the blobstore item' do
          expect {
            droplet_delete.delete(droplet_dataset)
          }.to change {
            Delayed::Job.count
          }.by(1)

          job = Delayed::Job.last
          expect(job.handler).to include('VCAP::CloudController::Jobs::Runtime::BlobstoreDelete')
          expect(job.handler).to include("key: #{droplet.blobstore_key}")
          expect(job.handler).to include('droplet_blobstore')
          expect(job.queue).to eq('cc-generic')
          expect(job.guid).not_to be_nil
        end
      end
    end
  end
end
