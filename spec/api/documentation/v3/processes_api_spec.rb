require 'spec_helper'
require 'awesome_print'
require 'rspec_api_documentation/dsl'

resource 'Processes (Experimental)', type: :api do
  let(:admin_auth_header) { admin_headers['HTTP_AUTHORIZATION'] }
  header 'AUTHORIZATION', :admin_auth_header

  def do_request_with_error_handling
    do_request
    if response_status == 500
      error = JSON.parse(response_body)
      ap error
      raise error['description']
    end
  end

  get '/v3/processes/:guid' do
    let(:process) { VCAP::CloudController::AppFactory.make }
    let(:guid) { process.guid }

    example 'Get a Process' do
      expected_response = {
        'guid'     => guid,
      }

      do_request_with_error_handling
      parsed_response = MultiJson.load(response_body)

      expect(response_status).to eq(200)
      expect(parsed_response).to match(expected_response)
    end
  end

  delete '/v3/processes/:guid' do
    let!(:process) { VCAP::CloudController::AppFactory.make }
    let(:guid) { process.guid }

    example 'Delete a Process' do
      expect {
        do_request_with_error_handling
      }.to change{ VCAP::CloudController::App.count }.by(-1)
      expect(response_status).to eq(204)
    end
  end

  patch '/v3/processes/:guid' do
    let(:process) { VCAP::CloudController::AppFactory.make }

    parameter :name, 'Name of process'
    parameter :memory, 'Amount of memory (MB) allocated to each instance'
    parameter :instances, 'Number of instances'
    parameter :disk_quota, 'Amount of disk space (MB) allocated to each instance'
    parameter :space_guid, 'Guid of associated Space'
    parameter :stack_guid, 'Guid of associated Stack'
    parameter :state, 'Desired state of process'
    parameter :command, 'Start command for process'
    parameter :buildpack, 'Buildpack used to stage process'
    parameter :health_check_timeout, 'Health check timeout for process'
    parameter :docker_image, 'Name of docker image containing process'
    parameter :environment_json, 'JSON key-value pairs for ENV variables'

    let(:name) { 'new_name' }
    let(:memory) { 2555 }
    let(:instances) { 2 }
    let(:disk_quota) { 2048 }
    let(:space_guid) { process.space.guid }
    let(:stack_guid) { process.stack.guid }
    let(:command) { 'X' }
    let(:guid) { process.guid }

    let(:raw_post) { MultiJson.dump(params, pretty: true) }

    example 'Updating a Process' do
      expected_response = {
        'guid' => guid,
      }
      do_request_with_error_handling
      parsed_response = JSON.parse(response_body)

      expect(response_status).to eq(200)
      expect(parsed_response).to match(expected_response)

      process.reload
      expect(process.name).to eq('new_name')
      expect(process.command).to eq('X')
      expect(process.memory).to eq(2555)
      expect(process.instances).to eq(2)
      expect(process.disk_quota).to eq(2048)
    end
  end

  post '/v3/processes' do
    let(:space) { VCAP::CloudController::Space.make }
    let(:stack) { VCAP::CloudController::Stack.make }

    parameter :name, 'Name of process', required: true
    parameter :memory, 'Amount of memory (MB) allocated to each instance', required: true
    parameter :instances, 'Number of instances', required: true
    parameter :disk_quota, 'Amount of disk space (MB) allocated to each instance', required: true
    parameter :space_guid, 'Guid of associated Space', required: true
    parameter :stack_guid, 'Guid of associated Stack', required: true
    parameter :state, 'Desired state of process'
    parameter :command, 'Start command for process'
    parameter :buildpack, 'Buildpack used to stage process'
    parameter :health_check_timeout, 'Health check timeout for process'
    parameter :docker_image, 'Name of docker image containing process'
    parameter :environment_json, 'JSON key-value pairs for ENV variables'

    let(:name) { 'process' }
    let(:memory) { 256 }
    let(:instances) { 2 }
    let(:disk_quota) { 1024 }
    let(:space_guid) { space.guid }
    let(:stack_guid) { stack.guid }

    let(:raw_post) { MultiJson.dump(params, pretty: true) }

    context 'without a docker image' do
      example 'Create a Process' do
        expected_response = {
          'guid' => /^[a-z0-9\-]+$/,
        }
        expect {
          do_request_with_error_handling
        }.to change{ VCAP::CloudController::App.count }.by(1)
        parsed_response = JSON.parse(response_body)

        expect(response_status).to eq(201)
        expect(parsed_response).to match(expected_response)
      end
    end

    context 'with a docker image' do
      let(:environment_json) { { 'CF_DIEGO_BETA' => 'true', 'CF_DIEGO_RUN_BETA' => 'true' } }
      let(:docker_image) { 'cloudfoundry/hello' }

      example 'Create a Docker Process' do
        expected_response = {
          'guid' => /^[a-z0-9\-]+$/,
        }
        expect {
          do_request_with_error_handling
        }.to change{ VCAP::CloudController::App.count }.by(1)
        parsed_response = JSON.parse(response_body)

        expect(response_status).to eq(201)
        expect(parsed_response).to match(expected_response)
      end
    end
  end
end
