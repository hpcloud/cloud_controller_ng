require 'json'
require 'spec_helper'
require 'rspec_api_documentation/dsl'
require "cloud_controller/stackato/droplet_accountability"

resource 'Spaces', type: [:api, :legacy_api] do
  parameter :guid, 'The guid of the Space'

  let(:admin_auth_header) { admin_headers['HTTP_AUTHORIZATION'] }
  let!(:space) { VCAP::CloudController::Space.make }
  let(:guid) { space.guid }

  authenticated_request

  get '/v2/spaces/:guid/usage' do
    let(:app1) { VCAP::CloudController::AppFactory.make(space: space, memory: 12) }
    let(:app2) { VCAP::CloudController::AppFactory.make(space: space, memory: 34) }

    example 'Get space usage statistics' do
      explanation <<-eos
        Get space runtime usage information
      eos
      expect(space.apps).to match_array([app1, app2])

      allow(VCAP::CloudController::StackatoDropletAccountability).to receive(:get_app_stats) do |app|
        expect([app1, app2]).to include(app)
        ({
          1 => {
            "state" => "RUNNING",
            "stats" => {
              "usage" => {
                "mem" => app.memory * 1024 * 1024 / 2 # megabytes -> bytes
              }
            }
          }
        })
      end

      do_request
      response_json = JSON.parse(response_body)
      expect(response_json["usage"]["mem"]).to be_within(0.01).of (12 + 34) * 1024.0 * 1024.0 / 2.0 # megabytes -> bytes
      expect(response_json["usage"]["memory_in_megabytes"]).to be_within(0.01).of (12 + 34) / 2.0
      expect(response_json["allocated"]["mem"]).to be_within(0.01).of (12 + 34) * 1024.0 # megabytes -> kilobytes
      expect(response_json["allocated"]["memory_in_megabytes"]).to be_within(0.01).of (12 + 34)
    end
  end
end
