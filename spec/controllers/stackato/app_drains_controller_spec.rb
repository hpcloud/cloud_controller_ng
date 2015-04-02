require 'spec_helper'
require 'stackato/spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoAppDrainsController, type: :controller do
    
    let(:app_obj)   { AppFactory.make }
    let(:developer) { make_developer_for_space(app_obj.space) }
    let(:headers)   { headers_for(developer) }
    let(:drain_name){ 'test_drain' }
    let(:drain_uri) { 'tcp://test.stackato.com/' }

    before do
      init_logyard_drains
      stub_logyard_request
    end

    describe "POST /v2/apps/:id/stackato_drains" do
      let(:req_body)  { MultiJson.dump({ drain: drain_name, uri: drain_uri }) }
      it "should crete app drains" do
        post "/v2/apps/#{app_obj.guid}/stackato_drains", req_body, headers
        expect(last_response.status).to eq(204)
      end
    end

    describe "GET /v2/apps/:id/stackato_drains" do
      before { VCAP::CloudController::StackatoAppDrains.create(app_obj, drain_name, drain_uri, nil) }
      after  { VCAP::CloudController::StackatoAppDrains.delete(app_obj, drain_name) }
      it "should query app drains" do
        get "/v2/apps/#{app_obj.guid}/stackato_drains", {}, headers
        expect(decoded_response.first["name"]).to include(drain_name)
        expect(decoded_response.first["uri"]).to eq(drain_uri)
        expect(last_response.status).to eq(200)
      end
    end

    describe "DELETE /v2/apps/:id/stackato_drains" do
      before { VCAP::CloudController::StackatoAppDrains.create(app_obj, drain_name, drain_uri, nil) }
      it "should delete app drain" do
        delete "/v2/apps/#{app_obj.guid}/stackato_drains/#{drain_name}", {}, headers
        expect(last_response.status).to eq(204)
      end
    end

  end
end 


