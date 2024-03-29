require 'spec_helper'

module VCAP::CloudController
  describe InstallBuildpacks do
    describe 'installs buildpacks' do
      let(:installer) { InstallBuildpacks.new(TestConfig.config) }
      let(:job) { double(Jobs::Runtime::BuildpackInstaller) }
      let(:job2) { double(Jobs::Runtime::BuildpackInstaller) }
      let(:enqueuer) { double(Jobs::Enqueuer) }
      let(:install_buildpack_config) do
        {
          install_buildpacks: [
            {
              'name' => 'buildpack1',
              'package' => 'mybuildpackpkg'
            },
          ]
        }
      end

      before do
        TestConfig.override(install_buildpack_config)
      end

      it 'enqueues a job to install a buildpack' do
        expect(Jobs::Runtime::BuildpackInstaller).to receive(:new).with('buildpack1', 'abuildpack.zip', {}).and_return(job)
        expect(job).to receive(:perform)
        expect(Dir).to receive(:[]).with('/var/vcap/packages/mybuildpackpkg/*.zip').and_return(['abuildpack.zip'])
        expect(File).to receive(:file?).with('abuildpack.zip').and_return(true)
        installer.install(TestConfig.config[:install_buildpacks])
      end

      it 'handles multiple buildpacks' do
        TestConfig.config[:install_buildpacks] << {
          'name' => 'buildpack2',
          'package' => 'myotherpkg'
        }

        expect(Jobs::Runtime::BuildpackInstaller).to receive(:new).with('buildpack1', 'abuildpack.zip', {}).ordered.and_return(job)
        expect(job).to receive(:perform)
        expect(Dir).to receive(:[]).with('/var/vcap/packages/mybuildpackpkg/*.zip').and_return(['abuildpack.zip'])
        expect(File).to receive(:file?).with('abuildpack.zip').and_return(true)

        expect(Jobs::Runtime::BuildpackInstaller).to receive(:new).with('buildpack2', 'otherbp.zip', {}).ordered.and_return(job2)
        expect(job2).to receive(:perform)
        expect(Dir).to receive(:[]).with('/var/vcap/packages/myotherpkg/*.zip').and_return(['otherbp.zip'])
        expect(File).to receive(:file?).with('otherbp.zip').and_return(true)

        installer.install(TestConfig.config[:install_buildpacks])
      end

      it 'logs an error when no buildpack zip file is found' do
        expect(Dir).to receive(:[]).with('/var/vcap/packages/mybuildpackpkg/*.zip').and_return([])
        expect(installer.logger).to receive(:error).with(/No file found for the buildpack/)

        installer.install(TestConfig.config[:install_buildpacks])
      end

      context 'when no buildpacks defined' do
        it 'succeeds without failure' do
          installer.install(nil)
        end
      end

      context 'override file location' do
        let(:install_buildpack_config) do
          {
            install_buildpacks: [
              {
                'name' => 'buildpack1',
                'package' => 'mybuildpackpkg',
                'file' => 'another.zip',
              },
            ]
          }
        end

        it 'uses the file override' do
          expect(Jobs::Runtime::BuildpackInstaller).to receive(:new).with('buildpack1', 'another.zip', {}).and_return(job)
          expect(job).to receive(:perform)
          expect(File).to receive(:file?).with('another.zip').and_return(true)
          installer.install(TestConfig.config[:install_buildpacks])
        end

        it 'fails when no buildpack zip file is found' do
          expect(installer.logger).to receive(:error).with(/File not found: another.zip/)

          installer.install(TestConfig.config[:install_buildpacks])
        end

        it 'succeeds when no package is specified' do
          TestConfig.config[:install_buildpacks][0].delete('package')

          expect(Jobs::Runtime::BuildpackInstaller).to receive(:new).with('buildpack1', 'another.zip', {}).and_return(job)
          expect(job).to receive(:perform)
          expect(File).to receive(:file?).with('another.zip').and_return(true)
          installer.install(TestConfig.config[:install_buildpacks])
        end
      end

      context 'missing required values' do
        it 'fails when no package is specified' do
          TestConfig.config[:install_buildpacks][0].delete('package')
          expect(installer.logger).to receive(:error).with(/A package or file must be specified/)

          installer.install(TestConfig.config[:install_buildpacks])
        end

        it 'fails when no name is specified' do
          TestConfig.config[:install_buildpacks][0].delete('name')
          expect(installer.logger).to receive(:error).with(/A name must be specified for the buildpack/)

          installer.install(TestConfig.config[:install_buildpacks])
        end
      end

      context 'additional options' do
        let(:install_buildpack_config) do
          {
            install_buildpacks: [
              {
                'name' => 'buildpack1',
                'package' => 'mybuildpackpkg',
                'enabled' => true,
                'locked' => false,
                'position' => 5,
              },
            ]
          }
        end

        it 'the config is valid' do
          # Merge note: stackato's :db/:database is declared to be an optional hash, upstream is a string,
          # but in lib/cloud_controller/config.rb we declare
          # :database/:db to be String, but set it to a string:
          # config[:db][:database] ||= ENV['DB_CONNECTION_STRING']
          TestConfig.config[:nginx][:instance_socket] = 'mysocket'
          if !TestConfig.config.fetch(:db,{})[:database].kind_of?(Hash)
            TestConfig.config[:db].delete(:database)
          end
          Config.schema.validate(TestConfig.config)
        end

        it 'passes optional attributes to the job' do
          expect(Jobs::Runtime::BuildpackInstaller).to receive(:new).
            with('buildpack1', 'abuildpack.zip', { enabled: true, locked: false, position: 5 }).and_return(job)
          expect(job).to receive(:perform)
          expect(Dir).to receive(:[]).with('/var/vcap/packages/mybuildpackpkg/*.zip').and_return(['abuildpack.zip'])
          expect(File).to receive(:file?).with('abuildpack.zip').and_return(true)
          installer.install(TestConfig.config[:install_buildpacks])
        end
      end
    end
  end
end
