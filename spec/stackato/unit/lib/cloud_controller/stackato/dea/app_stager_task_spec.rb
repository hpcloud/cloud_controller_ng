require 'spec_helper'

module VCAP::CloudController
  describe Dea::StackatoAppStagerTask do
    let(:message_bus) { CfMessageBus::MockMessageBus.new }
    let(:stager_pool) { double(:stager_pool, reserve_app_memory: nil) }
    let(:dea_pool) { double(:stager_pool, reserve_app_memory: nil) }
    let(:config_hash) { { staging: { timeout_in_seconds: 360 } } }
    let(:app) do
      AppFactory.make(
        package_hash:  'abc',
        droplet_hash:  nil,
        package_state: 'PENDING',
        state:         'STARTED',
        instances:     1,
        disk_quota:    1024
      )
    end
    let(:stager_id) { 'my_stager' }
    let(:blobstore_url_generator) { CloudController::DependencyLocator.instance.blobstore_url_generator }

    let(:options) { {} }
    subject(:staging_task) { Dea::StackatoAppStagerTask.new(config_hash, message_bus, app, dea_pool, stager_pool, blobstore_url_generator) }

    let(:first_reply_json_error) { nil }
    let(:task_streaming_log_url) { 'task-streaming-log-url' }

    let(:first_reply_json) do
      {
        'task_id'                => 'task-id',
        'task_log'               => 'task-log',
        'task_streaming_log_url' => task_streaming_log_url,
        'detected_buildpack'     => nil,
        'detected_start_command' => nil,
        'buildpack_key'          => nil,
        'error'                  => first_reply_json_error,
        'droplet_sha1'           => nil
      }
    end

    let(:reply_json_error) { nil }
    let(:reply_error_info) { nil }
    let(:detected_buildpack) { nil }
    let(:detected_start_command) { 'wait_for_godot' }
    let(:buildpack_key) { nil }

    let(:reply_json) do
      {
        'task_id'                => 'task-id',
        'task_log'               => 'task-log',
        'task_streaming_log_url' => nil,
        'detected_buildpack'     => detected_buildpack,
        'buildpack_key'          => buildpack_key,
        'detected_start_command' => detected_start_command,
        'error'                  => reply_json_error,
        'error_info'             => reply_error_info,
        'droplet_sha1'           => 'droplet-sha1'
      }
    end

    before do
      expect(app.staged?).to be false

      allow(VCAP).to receive(:secure_uuid) { 'some_task_id' }
      allow(stager_pool).to receive(:find_stager).with(app.stack.name, 1024, anything, 'default').and_return(stager_id)
      allow(EM).to receive(:add_timer)
      allow(EM).to receive(:defer).and_yield
      allow(EM).to receive(:schedule_sync)
    end

    describe 'staging' do
      context 'verifier' do
        before do
          allow(Kato::Cluster::Manager).to receive(:node_ids_for_process).with("dea_ng").and_return(["127.0.0.1"])
        end
        it 'verifies staging_task.available_placement_zones) is callable' do
          app.disk_quota                                  = 12
          config_hash[:staging][:minimum_staging_disk_mb] = 1025
          expect(stager_pool).to receive(:find_stager).with(app.stack.name, anything, 1025, 'default').and_return(stager_id)
          staging_task.stage
          expect(staging_task.available_placement_zones).to eq(["default"])
        end
      end
    end

    def ignore_staging_error
      yield
    rescue VCAP::Errors::ApiError => e
      raise e unless e.name == 'StagingError'
    end
  end
end
