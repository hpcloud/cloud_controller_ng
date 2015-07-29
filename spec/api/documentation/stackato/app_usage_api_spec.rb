require 'json'
require 'spec_helper'
require 'rspec_api_documentation/dsl'
require "cloud_controller/stackato/droplet_accountability"

resource 'Apps', type: [:api, :legacy_api] do
  parameter :guid, 'The guid of the App'

  let(:admin_auth_header) { admin_headers['HTTP_AUTHORIZATION'] }
  let(:space) { VCAP::CloudController::Space.make }
  let(:app_obj) { VCAP::CloudController::AppFactory.make(space: space, droplet_hash: nil, package_state: 'PENDING', memory: 12) }

  authenticated_request

  get '/v2/apps/:guid/usage' do
    let(:guid) { app_obj.guid }

    example 'Get application usage statistics' do
      explanation <<-eos
        Get application runtime usage information
      eos
      expect(VCAP::CloudController::StackatoDropletAccountability).to receive(:get_app_stats) do |app|
        expect(app).to eq(app_obj)
        ({
          1 => {
            "state" => "RUNNING",
            "stats" => {
              "usage" => {
                "mem" => (1.23 * 1024 * 1024).to_i # bytes
              }
            }
          }
        })
      end

      do_request
      response_json = JSON.parse(response_body)
      expect(response_json["usage"]["mem"]).to be_within(0.01).of 1.23 * 1024 # megabytes -> kilobytes
      expect(response_json["usage"]["memory_in_megabytes"]).to be_within(0.01).of 1.23
      expect(response_json["allocated"]["mem"]).to be_within(0.01).of 12 * 1024 # megabytes -> kilobytes
      expect(response_json["allocated"]["memory_in_megabytes"]).to be_within(0.01).of 12.0
    end
  end
end
