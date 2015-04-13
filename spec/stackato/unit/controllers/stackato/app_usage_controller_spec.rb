require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoAppUsageController, type: :controller do
    let(:app_obj) { AppFactory.make(package_hash: 'made-up-hash') }
    let(:developer) { make_developer_for_space(app_obj.space) }
    let(:headers)   { headers_for(developer) }

    it 'returns the amount the app is using' do
      get "/v2/apps/#{app_obj.guid}/usage", {}, headers
      expect(last_response.status).to eq(200)
      amts = Yajl::Parser.parse(last_response.body)
      expect(amts["usage"]["mem"]).to eq(0)
      expect(amts["allocated"]["mem"]).to eq(1048576)
    end
  end
end

