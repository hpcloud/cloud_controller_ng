require 'spec_helper'
require 'actions/droplet_copy'

module VCAP::CloudController
  describe DropletCopy do
    let(:droplet_copy) { DropletCopy.new(source_droplet) }
    let(:source_space) { VCAP::CloudController::Space.make }
    let(:target_app) { VCAP::CloudController::AppModel.make }
    let(:source_app_guid) { VCAP::CloudController::AppModel.make(name: 'source-app-name', space_guid: source_space.guid) }
    let(:lifecycle_type) { :buildpack }
    let!(:source_droplet) { VCAP::CloudController::DropletModel.make(lifecycle_type,
      app_guid: source_app_guid,
      droplet_hash: 'abcdef',
      process_types: { web: 'bundle exec rails s' },
      environment_variables: { 'THING' => 'STUFF' })
    }
    let(:perform_copying) { droplet_copy.copy(target_app.guid,
                                              'user-guid',
                                              'user-email',
                                              source_app_guid,
                                              'source-app-name',
                                              target_app.space_guid,
                                              target_app.space.organization_guid
                                             )
    }

    describe '#copy' do
      it 'copies the passed in droplet to the target app' do
        expect {
          perform_copying
        }.to change { DropletModel.count }.by(1)

        copied_droplet = DropletModel.last

        expect(copied_droplet.state).to eq DropletModel::PENDING_STATE
        expect(copied_droplet.buildpack_receipt_buildpack_guid).to eq source_droplet.buildpack_receipt_buildpack_guid
        expect(copied_droplet.droplet_hash).to be nil
        expect(copied_droplet.detected_start_command).to eq source_droplet.detected_start_command
        expect(copied_droplet.environment_variables).to eq(nil)
        expect(copied_droplet.process_types).to eq({ 'web' => 'bundle exec rails s' })
        expect(copied_droplet.buildpack_receipt_buildpack).to eq source_droplet.buildpack_receipt_buildpack
        expect(copied_droplet.buildpack_receipt_stack_name).to eq source_droplet.buildpack_receipt_stack_name
        expect(copied_droplet.execution_metadata).to eq source_droplet.execution_metadata
        expect(copied_droplet.memory_limit).to eq source_droplet.memory_limit
        expect(copied_droplet.disk_limit).to eq source_droplet.disk_limit
        expect(copied_droplet.docker_receipt_image).to eq source_droplet.docker_receipt_image

        expect(target_app.droplets).to include(copied_droplet)
      end

      it 'creates an audit event' do
        expect(Repositories::DropletEventRepository).to receive(:record_create_by_copying).with(
          target_app.guid,
          source_droplet.guid,
          'user-guid',
          'user-email',
          source_app_guid,
          'source-app-name',
          target_app.space_guid,
          target_app.space.organization_guid
        )

        perform_copying
      end

      context 'when lifecycle is buildpack' do
        it 'creates a buildpack_lifecycle_data record for the new droplet' do
          expect {
            perform_copying
          }.to change { BuildpackLifecycleDataModel.count }.by(1)

          copied_droplet = DropletModel.last

          expect(copied_droplet.buildpack_lifecycle_data.stack).not_to be nil
          expect(copied_droplet.buildpack_lifecycle_data.stack).to eq(source_droplet.buildpack_lifecycle_data.stack)
        end

        it 'enqueues a job to copy the droplet bits' do
          copied_droplet = nil

          expect {
            copied_droplet = perform_copying
          }.to change { Delayed::Job.count }.by(1)

          job = Delayed::Job.last
          expect(job.queue).to eq('cc-generic')
          expect(job.handler).to include(copied_droplet.guid)
          expect(job.handler).to include(source_droplet.guid)
          expect(job.handler).to include('DropletBitsCopier')
        end
      end

      context 'when lifecycle is docker' do
        let(:lifecycle_type) { :docker }

        it 'raises an ApiError' do
          expect {
            perform_copying
          }.to raise_error(CloudController::Errors::ApiError)
        end
      end
    end
  end
end
