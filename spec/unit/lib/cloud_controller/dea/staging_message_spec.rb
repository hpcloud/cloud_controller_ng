require 'spec_helper'

module VCAP::CloudController
  describe Dea::StagingMessage do
    let(:blobstore_url_generator) { CloudController::DependencyLocator.instance.blobstore_url_generator }
    let(:config_hash) { { staging: { timeout_in_seconds: 360 } } }
    let(:task_id) { 'somthing' }
    let(:droplet_guid) { 'abc123' }
    let(:log_id) { 'log-id' }
    let(:docker_registry) { "localhost:5000" }
    let(:staging_message) { Dea::StagingMessage.new(config_hash, blobstore_url_generator, docker_registry) }

    before do
      SecurityGroup.make(rules: [{ 'protocol' => 'udp', 'ports' => '8080-9090', 'destination' => '198.41.191.47/1' }], staging_default: true)
      SecurityGroup.make(rules: [{ 'protocol' => 'tcp', 'ports' => '8080-9090', 'destination' => '198.41.191.48/1' }], staging_default: true)
      SecurityGroup.make(rules: [{ 'protocol' => 'tcp', 'ports' => '80',        'destination' => '0.0.0.0/0' }], staging_default: false)
    end

    describe Dea::PackageDEAStagingMessage do
      let(:package) { PackageModel.make }
      let(:stack) { 'trusty32' }
      let(:memory_limit) { 1234 }
      let(:disk_limit) { 321 }
      let(:buildpack_key) { 'buildpack_key' }
      let(:buildpack_git_url) { 'http://git.url' }
      subject(:staging_message) do
        Dea::PackageDEAStagingMessage.new(
          package, droplet_guid, log_id, stack, memory_limit, disk_limit,
          buildpack_key, buildpack_git_url, config_hash, blobstore_url_generator, docker_registry)
      end

      its(:stack) { should eq('trusty32') }
      its(:memory_limit) { should eq(1234) }
      its(:disk_limit) { should eq(321) }
      its(:buildpack_key) { should eq('buildpack_key') }
      its(:buildpack_git_url) { should eq('http://git.url') }
      its(:log_id) { should eq('log-id') }
      its(:droplet_guid) { should eq('abc123') }

      describe '#staging_request' do
        it 'includes app guid, task id, download/upload uris, buildpack_key, stack' do
          allow(blobstore_url_generator).to receive(:package_download_url).with(package).and_return('http://www.package.uri')
          allow(blobstore_url_generator).to receive(:package_droplet_upload_url).with(droplet_guid).and_return('http://www.droplet.upload.uri')
          allow(blobstore_url_generator).to receive(:package_buildpack_cache_upload_url).with(package).and_return('http://www.bpupload.uri')
          allow(blobstore_url_generator).to receive(:package_buildpack_cache_download_url).with(package).and_return('http://www.bpdownload.uri')
          request = staging_message.staging_request

          expect(request[:app_id]).to eq(log_id)
          expect(request[:task_id]).to eq(droplet_guid)
          expect(request[:download_uri]).to eq('http://www.package.uri')
          expect(request[:upload_uri]).to eq('http://www.droplet.upload.uri')
          expect(request[:buildpack_cache_download_uri]).to eq('http://www.bpdownload.uri')
          expect(request[:buildpack_cache_upload_uri]).to eq('http://www.bpupload.uri')
          expect(request[:properties][:buildpack_key]).to eq('buildpack_key')
          expect(request[:properties][:buildpack_git_url]).to eq('http://git.url')
          expect(request[:stack]).to eq('trusty32')
          expect(request[:memory_limit]).to eq(memory_limit)
          expect(request[:disk_limit]).to eq(disk_limit)
        end

        it 'includes egress security group staging information by aggregating all sg with staging_default=true' do
          request = staging_message.staging_request
          expect(request[:egress_network_rules]).to match_array([
            { 'protocol' => 'udp', 'ports' => '8080-9090', 'destination' => '198.41.191.47/1' },
            { 'protocol' => 'tcp', 'ports' => '8080-9090', 'destination' => '198.41.191.48/1' }
          ])
        end

        describe 'the list of admin buildpacks' do
          let!(:buildpack_a) { Buildpack.make(key: 'a key', position: 2) }
          let!(:buildpack_b) { Buildpack.make(key: 'b key', position: 1) }
          let!(:buildpack_c) { Buildpack.make(key: 'c key', position: 4) }

          let(:buildpack_file_1) { Tempfile.new('admin buildpack 1') }
          let(:buildpack_file_2) { Tempfile.new('admin buildpack 2') }
          let(:buildpack_file_3) { Tempfile.new('admin buildpack 3') }

          let(:buildpack_blobstore) { CloudController::DependencyLocator.instance.buildpack_blobstore }

          before do
            buildpack_blobstore.cp_to_blobstore(buildpack_file_1.path, 'a key')
            buildpack_blobstore.cp_to_blobstore(buildpack_file_2.path, 'b key')
            buildpack_blobstore.cp_to_blobstore(buildpack_file_3.path, 'c key')
          end

          it 'includes a list of admin buildpacks as hashes containing its blobstore URI and key' do
            Timecop.freeze do # download_uri have an expire_at
              request = staging_message.staging_request

              admin_buildpacks = request[:admin_buildpacks]

              expect(admin_buildpacks).to have(3).items
              expect(admin_buildpacks).to include(url: buildpack_blobstore.download_uri('a key'), key: 'a key')
              expect(admin_buildpacks).to include(url: buildpack_blobstore.download_uri('b key'), key: 'b key')
              expect(admin_buildpacks).to include(url: buildpack_blobstore.download_uri('c key'), key: 'c key')
            end
          end
        end
      end
    end

    describe '.staging_request' do
      let(:app) { AppFactory.make droplet_hash: nil, package_state: 'PENDING' }

      before do
        3.times do
          instance = ManagedServiceInstance.make(space: app.space)
          binding = ServiceBinding.make(app: app, service_instance: instance)
          app.add_service_binding(binding)
        end
      end

      it 'includes app guid, task id, download/upload uris and stack name' do
        allow(blobstore_url_generator).to receive(:app_package_download_url).with(app).and_return('http://www.app.uri')
        allow(blobstore_url_generator).to receive(:droplet_upload_url).with(app).and_return('http://www.droplet.upload.uri')
        allow(blobstore_url_generator).to receive(:buildpack_cache_download_url).with(app).and_return('http://www.buildpack.cache.download.uri')
        allow(blobstore_url_generator).to receive(:buildpack_cache_upload_url).with(app).and_return('http://www.buildpack.cache.upload.uri')
        request = staging_message.staging_request(app, task_id)

        expect(request[:app_id]).to eq(app.guid)
        expect(request[:task_id]).to eq(task_id)
        expect(request[:download_uri]).to eq('http://www.app.uri')
        expect(request[:upload_uri]).to eq('http://www.droplet.upload.uri')
        expect(request[:buildpack_cache_upload_uri]).to eq('http://www.buildpack.cache.upload.uri')
        expect(request[:buildpack_cache_download_uri]).to eq('http://www.buildpack.cache.download.uri')
        expect(request[:stack]).to eq(app.stack.name)
      end

      it 'includes misc app properties' do
        request = staging_message.staging_request(app, task_id)
        expect(request[:properties][:meta]).to be_kind_of(Hash)
      end

      it 'includes service binding properties' do
        request = staging_message.staging_request(app, task_id)
        expect(request[:properties][:services].count).to eq(3)
        request[:properties][:services].each do |service|
          expect(service[:credentials]).to be_kind_of(Hash)
          expect(service[:options]).to be_kind_of(Hash)
        end
      end

      context 'when app does not have buildpack' do
        it 'returns nil for buildpack' do
          app.buildpack = nil
          request = staging_message.staging_request(app, task_id)
          expect(request[:properties][:buildpack]).to be_nil
        end
      end

      context 'when app has a buildpack' do
        it 'returns url for buildpack' do
          app.buildpack = 'git://example.com/foo.git'
          request = staging_message.staging_request(app, task_id)
          expect(request[:properties][:buildpack]).to eq('git://example.com/foo.git')
          expect(request[:properties][:buildpack_git_url]).to eq('git://example.com/foo.git')
        end

        it "doesn't return a buildpack key" do
          app.buildpack = 'git://example.com/foo.git'
          request = staging_message.staging_request(app, task_id)
          expect(request[:properties]).to_not have_key(:buildpack_key)
        end
      end

      it 'includes start app message' do
        request = staging_message.staging_request(app, task_id)
        expect(request[:start_message]).to be_a(Dea::StartAppMessage)
      end

      it 'includes app index 0' do
        request = staging_message.staging_request(app, task_id)
        expect(request[:start_message]).to include({ index: 0 })
      end

      it 'overwrites droplet sha' do
        request = staging_message.staging_request(app, task_id)
        expect(request[:start_message]).to include({ sha1: nil })
      end

      it 'overwrites droplet download uri' do
        request = staging_message.staging_request(app, task_id)
        expect(request[:start_message]).to include({ executableUri: nil })
      end

      describe 'the list of admin buildpacks' do
        let!(:buildpack_a) { Buildpack.make(key: 'a key', position: 2) }
        let!(:buildpack_b) { Buildpack.make(key: 'b key', position: 1) }
        let!(:buildpack_c) { Buildpack.make(key: 'c key', position: 4) }

        let(:buildpack_file_1) { Tempfile.new('admin buildpack 1') }
        let(:buildpack_file_2) { Tempfile.new('admin buildpack 2') }
        let(:buildpack_file_3) { Tempfile.new('admin buildpack 3') }

        let(:buildpack_blobstore) { CloudController::DependencyLocator.instance.buildpack_blobstore }

        before do
          buildpack_blobstore.cp_to_blobstore(buildpack_file_1.path, 'a key')
          buildpack_blobstore.cp_to_blobstore(buildpack_file_2.path, 'b key')
          buildpack_blobstore.cp_to_blobstore(buildpack_file_3.path, 'c key')
        end

        context 'when a specific buildpack is not requested' do
          it 'includes a list of admin buildpacks as hashes containing its blobstore URI and key' do
            Timecop.freeze do # download_uri have an expire_at
              request = staging_message.staging_request(app, task_id)

              admin_buildpacks = request[:admin_buildpacks]

              expect(admin_buildpacks).to have(3).items
              expect(admin_buildpacks).to include(url: buildpack_blobstore.download_uri('a key'), key: 'a key')
              expect(admin_buildpacks).to include(url: buildpack_blobstore.download_uri('b key'), key: 'b key')
              expect(admin_buildpacks).to include(url: buildpack_blobstore.download_uri('c key'), key: 'c key')
            end
          end
        end

        context 'when a specific buildpack is requested' do
          before do
            app.buildpack = Buildpack.first.name
            app.save
          end

          it "includes a list of admin buildpacks so that the system doesn't think the buildpacks are gone" do
            request = staging_message.staging_request(app, task_id)

            admin_buildpacks = request[:admin_buildpacks]

            expect(admin_buildpacks).to have(3).items
          end
        end

        context 'when a buildpack is disabled' do
          before do
            buildpack_a.enabled = false
            buildpack_a.save
          end

          context 'when a specific buildpack is not requested' do
            it 'includes a list of enabled admin buildpacks as hashes containing its blobstore URI and key' do
              Timecop.freeze do # download_uri have an expire_at
                request = staging_message.staging_request(app, task_id)

                admin_buildpacks = request[:admin_buildpacks]

                expect(admin_buildpacks).to have(2).items
                expect(admin_buildpacks).to include(url: buildpack_blobstore.download_uri('b key'), key: 'b key')
                expect(admin_buildpacks).to include(url: buildpack_blobstore.download_uri('c key'), key: 'c key')
              end
            end
          end

          context 'when a buildpack has missing bits' do
            it 'does not include the buildpack' do
              Buildpack.make(key: 'd key', position: 5)

              request = staging_message.staging_request(app, task_id)
              admin_buildpacks = request[:admin_buildpacks]
              expect(admin_buildpacks).to have(2).items
              expect(admin_buildpacks).to_not include(key: 'd key', url: nil)
            end
          end
        end
      end

      it 'includes the key of an admin buildpack when the app has a buildpack specified' do
        buildpack = Buildpack.make
        app.buildpack = buildpack.name
        app.save

        request = staging_message.staging_request(app, task_id)
        expect(request[:properties][:buildpack_key]).to eql buildpack.key
      end

      it "doesn't include the custom buildpack url keys when the app has a buildpack specified" do
        buildpack = Buildpack.make
        app.buildpack = buildpack.name
        app.save

        request = staging_message.staging_request(app, task_id)
        expect(request[:properties]).to_not have_key(:buildpack)
        expect(request[:properties]).to_not have_key(:buildpack_git_url)
      end

      it 'includes egress security group staging information by aggregating all sg with staging_default=true' do
        request = staging_message.staging_request(app, task_id)
        expect(request[:egress_network_rules]).to match_array([
          { 'protocol' => 'udp', 'ports' => '8080-9090', 'destination' => '198.41.191.47/1' },
          { 'protocol' => 'tcp', 'ports' => '8080-9090', 'destination' => '198.41.191.48/1' }
        ])
      end

      describe 'environment variables' do
        before do
          app.environment_json   = { 'KEY' => 'value' }
        end

        it 'includes app environment variables' do
          request = staging_message.staging_request(app, task_id)
          expect(request[:properties][:environment]).to include('KEY=value')
        end

        it 'includes environment variables from staging environment variable group' do
          group = EnvironmentVariableGroup.staging
          group.environment_json = { 'STAGINGKEY' => 'staging_value' }
          group.save

          request = staging_message.staging_request(app, task_id)
          expect(request[:properties][:environment]).to include('KEY=value', 'STAGINGKEY=staging_value')
        end

        it 'includes CF_STACK' do
          app.environment_json = { 'CF_STACK' => 'not-this' }

          request = staging_message.staging_request(app, task_id)
          expect(request[:properties][:environment]).to include("CF_STACK=#{app.stack.name}")
        end

        it 'prefers app environment variables when they conflict with staging group variables' do
          group = EnvironmentVariableGroup.staging
          group.environment_json = { 'KEY' => 'staging_value' }
          group.save

          request = staging_message.staging_request(app, task_id)
          expect(request[:properties][:environment]).to include('KEY=value')
        end
      end
    end
  end
end
