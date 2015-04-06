require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoSpaceUsageController, type: :controller do
    let(:space) { Space.make }
    let(:app_obj_1) { AppFactory.make(package_hash: 'hash1') }
    let(:app_obj_2) { AppFactory.make(package_hash: 'hash2') }
    let(:developer) { make_developer_for_space(space) }
    let(:headers)   { headers_for(developer) }

    it 'returns the amount the app is using' do
      # Instantiate the apps and hook them to the space we're testing
      app_obj_1.space = space
      app_obj_1.save
      app_obj_2.space = space
      app_obj_2.save
      get "/v2/spaces/#{space.guid}/usage", {}, headers

      expect(last_response.status).to eq(200)
      amts = Yajl::Parser.parse(last_response.body)
      expect(amts["usage"]["mem"]).to eq(0)
      expect(amts["allocated"]["mem"]).to eq(1048576 * 2)
    end
  end
end

