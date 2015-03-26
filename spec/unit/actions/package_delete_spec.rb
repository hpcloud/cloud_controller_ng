require 'spec_helper'
require 'actions/package_delete'

module VCAP::CloudController
  describe PackageDelete do
    subject(:package_delete) { PackageDelete.new }

    describe '#delete' do
      context 'when the package exists' do
        let!(:package) { PackageModel.make }
        let(:package_dataset) { PackageModel.where(guid: package.guid) }

        it 'deletes the package record' do
          expect {
            package_delete.delete(package_dataset)
          }.to change { PackageModel.count }.by(-1)
          expect { package.refresh }.to raise_error Sequel::Error, 'Record not found'
        end

        it 'schedules a job to the delete the blobstore item' do
          expect {
            package_delete.delete(package_dataset)
          }.to change {
            Delayed::Job.count
          }.by(1)

          job = Delayed::Job.last
          expect(job.handler).to include('VCAP::CloudController::Jobs::Runtime::BlobstoreDelete')
          expect(job.handler).to include("key: #{package.guid}")
          expect(job.handler).to include('package_blobstore')
          expect(job.queue).to eq('cc-generic')
          expect(job.guid).not_to be_nil
        end
      end

      context 'when passed a set of packages' do
        it 'bulk deletes them' do
          packages = []
          packages << PackageModel.make
          packages << PackageModel.make

          expect {
            package_delete.delete(PackageModel.dataset)
          }.to change {
            PackageModel.count
          }.by(-2)
        end
      end
    end
  end
end
