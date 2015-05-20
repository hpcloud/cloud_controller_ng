require 'spec_helper'
require 'handlers/droplets_handler'

module VCAP::CloudController
  describe StagingMessage do
    let(:package_guid) { 'package-guid' }
    let(:memory_limit) { 1024 }

    describe 'create_from_http_request' do
      context 'when the body is valid json' do
        let(:body) { MultiJson.dump({ memory_limit: memory_limit }) }

        it 'creates a StagingMessage from the json' do
          staging_message = StagingMessage.create_from_http_request(package_guid, body)
          valid, errors   = staging_message.validate

          expect(valid).to be_truthy
          expect(errors).to be_empty
        end
      end

      context 'when the body is not valid json' do
        let(:body) { '{{' }

        it 'returns a StagingMessage that is not valid' do
          staging_message = StagingMessage.create_from_http_request(package_guid, body)
          valid, errors   = staging_message.validate

          expect(valid).to be_falsey
          expect(errors[0]).to include('parse error')
        end
      end
    end

    context 'when only required fields are provided' do
      let(:body) { '{}' }

      it 'is valid' do
        psm           = StagingMessage.create_from_http_request(package_guid, body)
        valid, errors = psm.validate
        expect(valid).to be_truthy
        expect(errors).to be_empty
      end

      it 'provides default values' do
        psm = StagingMessage.create_from_http_request(package_guid, body)

        expect(psm.memory_limit).to eq(1024)
        expect(psm.disk_limit).to eq(4096)
        expect(psm.stack).to eq(Stack.default.name)
      end
    end

    context 'when memory_limit is not an integer' do
      let(:body) { MultiJson.dump({ memory_limit: 'stringsarefun' }) }

      it 'is not valid' do
        psm           = StagingMessage.create_from_http_request(package_guid, body)
        valid, errors = psm.validate
        expect(valid).to be_falsey
        expect(errors[0]).to include('must be an Integer')
      end
    end

    context 'when disk_limit is not an integer' do
      let(:body) { MultiJson.dump({ disk_limit: 'stringsarefun' }) }

      it 'is not valid' do
        psm           = StagingMessage.create_from_http_request(package_guid, body)
        valid, errors = psm.validate
        expect(valid).to be_falsey
        expect(errors[0]).to include('must be an Integer')
      end
    end

    context 'when stack is not a string' do
      let(:body) { MultiJson.dump({ stack: 1024 }) }

      it 'is not valid' do
        psm           = StagingMessage.create_from_http_request(package_guid, body)
        valid, errors = psm.validate
        expect(valid).to be_falsey
        expect(errors[0]).to include('must be a String')
      end
    end

    context 'when buildpack_git_url is not a valid url' do
      let(:body) { MultiJson.dump({ buildpack_git_url: 'blagow!' }) }

      it 'is not valid' do
        psm           = StagingMessage.create_from_http_request(package_guid, body)
        valid, errors = psm.validate
        expect(valid).to be_falsey
        expect(errors[0]).to include('must be a valid URI')
      end
    end

    context 'when buildpack_guid is not a string' do
      let(:body) { MultiJson.dump({ buildpack_guid: 1024 }) }

      it 'is not valid' do
        psm           = StagingMessage.create_from_http_request(package_guid, body)
        valid, errors = psm.validate
        expect(valid).to be_falsey
        expect(errors[0]).to include('must be a String')
      end
    end

    context 'when both buildpack_git_url and buildpack_guid are provided' do
      let(:body) { MultiJson.dump({ buildpack_guid: 'some-guid', buildpack_git_url: 'http://www.slashdot.org' }) }

      it 'is not valid' do
        psm           = StagingMessage.create_from_http_request(package_guid, body)
        valid, errors = psm.validate
        expect(valid).to be_falsey
        expect(errors[0]).to include('Only one of buildpack_git_url or buildpack_guid may be provided')
      end
    end
  end

  describe DropletsHandler do
    let(:config) { TestConfig.config }
    let(:stagers) { double(:stagers) }
    let(:droplets_handler) { described_class.new(config, stagers) }
    let(:user) { User.make }
    let(:access_context) { double(:access_context) }

    before do
      allow(access_context).to receive(:cannot?).and_return(false)
      allow(access_context).to receive(:user).and_return(user)
    end

    describe '#list' do
      let(:space) { Space.make }
      let(:app_model) { AppModel.make(space_guid: space.guid) }
      let!(:droplet1) { DropletModel.make(app_guid: app_model.guid) }
      let!(:droplet2) { DropletModel.make(app_guid: app_model.guid) }
      let(:user) { User.make }
      let(:page) { 1 }
      let(:per_page) { 1 }
      let(:options) { { page: page, per_page: per_page } }
      let(:pagination_options) { PaginationOptions.new(options) }
      let(:paginator) { double(:paginator) }

      let(:handler) { described_class.new(nil, nil, paginator) }
      let(:roles) { double(:roles, admin?: admin_role) }
      let(:admin_role) { false }

      before do
        allow(access_context).to receive(:roles).and_return(roles)
        allow(access_context).to receive(:user).and_return(user)
        allow(paginator).to receive(:get_page)
      end

      context 'when the user is an admin' do
        let(:admin_role) { true }
        before do
          allow(access_context).to receive(:roles).and_return(roles)
          DropletModel.make
        end

        it 'allows viewing all droplets' do
          handler.list(pagination_options, access_context)
          expect(paginator).to have_received(:get_page) do |dataset, _|
            expect(dataset.count).to eq(3)
          end
        end
      end

      context 'when the user cannot list any droplets' do
        it 'applies a user visibility filter properly' do
          handler.list(pagination_options, access_context)
          expect(paginator).to have_received(:get_page) do |dataset, _|
            expect(dataset.count).to eq(0)
          end
        end
      end

      context 'when the user can list droplets' do
        before do
          space.organization.add_user(user)
          space.add_developer(user)
          DropletModel.make
        end

        it 'applies a user visibility filter properly' do
          handler.list(pagination_options, access_context)
          expect(paginator).to have_received(:get_page) do |dataset, _|
            expect(dataset.count).to eq(2)
          end
        end
      end
    end

    describe '#create' do
      let(:space) { Space.make }
      let(:app_model) { AppModel.make(space_guid: space.guid, environment_variables: { 'APP_VAR' => 'is here' }) }
      let(:app_guid) { app_model.guid }
      let!(:package) { PackageModel.make(app_guid: app_guid, state: PackageModel::READY_STATE, type: PackageModel::BITS_TYPE) }
      let(:package_guid) { package.guid }
      let(:stack) { 'trusty32' }
      let(:memory_limit) { 12340 }
      let(:disk_limit) { 32100 }
      let(:disk_limit) { 32100 }
      let(:buildpack_guid) { nil }
      let(:buildpack_key) { nil }
      let(:buildpack_git_url) { 'something' }
      let(:body) do
        {
          stack:             stack,
          memory_limit:      memory_limit,
          disk_limit:        disk_limit,
          buildpack_guid:    buildpack_guid,
          buildpack_git_url: buildpack_git_url,
        }.stringify_keys
      end
      let(:staging_message) { StagingMessage.new(package_guid, body) }
      let(:stager) { double(:stager) }

      before do
        allow(stagers).to receive(:stager_for_package).with(package).and_return(stager)
        allow(stager).to receive(:stage_package)
        EnvironmentVariableGroup.make(name: :staging, environment_json: { 'another' => 'var', 'STAGING_ENV' => 'staging_value' })
      end

      context 'when the package exists' do
        context 'and the user is a space developer' do
          let(:buildpack) { Buildpack.make }
          let(:buildpack_guid) { buildpack.guid }
          let(:buildpack_key) { buildpack.key }

          it 'creates a droplet' do
            droplet = nil
            expect {
              droplet = droplets_handler.create(staging_message, access_context)
            }.to change(DropletModel, :count).by(1)
            expect(droplet.state).to eq(DropletModel::PENDING_STATE)
            expect(droplet.package_guid).to eq(package_guid)
            expect(droplet.buildpack_git_url).to eq('something')
            expect(droplet.buildpack_guid).to eq(buildpack_guid)
            expect(droplet.app_guid).to eq(app_guid)
          end

          it 'initiates a staging request' do
            droplets_handler.create(staging_message, access_context)
            droplet = DropletModel.last
            expect(stager).to have_received(:stage_package).with(droplet, stack, memory_limit, disk_limit, buildpack_key, buildpack_git_url)
          end
        end

        context 'environment variables' do
          it 'records the evironment variables used for staging' do
            app_model.environment_variables = app_model.environment_variables.merge({ 'another' => 'override' })
            app_model.save
            droplet = droplets_handler.create(staging_message, access_context)
            expect(droplet.environment_variables).to match({
              'another'     => 'override',
              'APP_VAR'     => 'is here',
              'STAGING_ENV' => 'staging_value',
              'CF_STACK' => stack,
              'VCAP_APPLICATION' => {
                'limits' => {
                  'mem' => staging_message.memory_limit,
                  'disk' => staging_message.disk_limit,
                  'fds' => 16384
                },
                'application_name' => app_model.name,
                'name' => app_model.name,
                'application_uris' => [],
                'uris' => [],
                'application_version' => /^[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}$/,
                'version' => /^[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}$/,
                'space_name' => space.name,
                'space_id' => space.guid,
                'users' => nil
              }
            })
          end

          context 'when the app has a route associated with it' do
            it 'sends the uris of the app as part of vcap_application' do
              route1 = Route.make(space: space)
              route2 = Route.make(space: space)
              route_adder = AddRouteToApp.new(app_model)
              route_adder.add(route1)
              route_adder.add(route2)

              droplet = droplets_handler.create(staging_message, access_context)
              expect(droplet.environment_variables['VCAP_APPLICATION']['uris']).to match([route1.fqdn, route2.fqdn])
              expect(droplet.environment_variables['VCAP_APPLICATION']['application_uris']).to match([route1.fqdn, route2.fqdn])
            end
          end

          context 'when instance_file_descriptor_limit is set' do
            it 'uses that value as the fds for staging' do
              TestConfig.config[:instance_file_descriptor_limit] = 100
              droplet = droplets_handler.create(staging_message, access_context)
              expect(droplet.environment_variables['VCAP_APPLICATION']['limits']).to include({
                'fds' => TestConfig.config[:instance_file_descriptor_limit]
              })
            end
          end
        end

        context 'and the user is not a space developer' do
          before do
            allow(access_context).to receive(:cannot?).and_return(true)
          end

          it 'fails with Unauthorized' do
            expect {
              droplets_handler.create(staging_message, access_context)
            }.to raise_error(DropletsHandler::Unauthorized)
            expect(access_context).to have_received(:cannot?).with(:create, kind_of(DropletModel), space)
          end
        end
      end

      context 'when the package type is not bits' do
        before do
          package.update(type: PackageModel::DOCKER_TYPE)
        end

        it 'fails with InvalidRequest' do
          expect {
            droplets_handler.create(staging_message, access_context)
          }.to raise_error(DropletsHandler::InvalidRequest)
        end
      end

      context 'when the package is not ready' do
        before do
          package.update(state: PackageModel::CREATED_STATE)
        end

        it 'fails with InvalidRequest' do
          expect {
            droplets_handler.create(staging_message, access_context)
          }.to raise_error(DropletsHandler::InvalidRequest)
        end
      end

      context 'when the package does not exist' do
        let(:package_guid) { 'non-existant' }

        it 'fails with PackageNotFound' do
          expect {
            droplets_handler.create(staging_message, access_context)
          }.to raise_error(DropletsHandler::PackageNotFound)
        end
      end

      context 'when a specific admin buildpack is requested' do
        context 'and the buildpack exists' do
          let(:buildpack) { Buildpack.make }
          let(:buildpack_guid) { buildpack.guid }
          let(:buildpack_key) { buildpack.key }

          it 'initiates the correct staging request' do
            droplets_handler.create(staging_message, access_context)
            droplet = DropletModel.last
            expect(stager).to have_received(:stage_package).with(droplet, stack, memory_limit, disk_limit, buildpack_key, buildpack_git_url)
          end
        end

        context 'and the buildpack does not exist' do
          let(:buildpack_guid) { 'not-real' }

          it 'raises BuildpackNotFound' do
            expect {
              droplets_handler.create(staging_message, access_context)
            }.to raise_error(DropletsHandler::BuildpackNotFound)
          end
        end
      end
    end

    describe 'show' do
      context 'when the droplet exists' do
        let(:droplet) { DropletModel.make }
        let(:droplet_guid) { droplet.guid }

        context 'and the user has permissions to read' do
          it 'returns the droplet' do
            expect(access_context).to receive(:cannot?).and_return(false)
            expect(droplets_handler.show(droplet_guid, access_context)).to eq(droplet)
          end
        end

        context 'and the user does not have permissions to read' do
          it 'raises an Unathorized exception' do
            expect(access_context).to receive(:cannot?).and_return(true)
            expect {
              droplets_handler.show(droplet_guid, access_context)
            }.to raise_error(DropletsHandler::Unauthorized)
          end
        end
      end

      context 'when the droplet does not exist' do
        it 'returns nil' do
          expect(access_context).not_to receive(:cannot?)
          expect(droplets_handler.show('bogus-droplet', access_context)).to be_nil
        end
      end
    end
  end
end
