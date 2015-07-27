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
      it "should create app drains" do
        post "/v2/apps/#{app_obj.guid}/stackato_drains", req_body, headers
        expect(last_response.status).to eq(204)
        expect(Kato::Config.get("logyard", "drains").size).to be > 0
        expect(Kato::Config.get("logyard", "drains").keys.first).to match(/test_drain/)
      end

      context "complain about disallowed drains" do
        let(:file_drain_uri) { 'file:///s/logs/debug-1.log' }
        let(:file_req_body)  { MultiJson.dump({ drain: drain_name, uri: file_drain_uri }) }
        let(:redis_drain_uri) { 'redis://192.168.1.157:5000' }
        let(:redis_req_body)  { MultiJson.dump({ drain: drain_name, uri: redis_drain_uri }) }

        it "should complain about a file drain" do
          post "/v2/apps/#{app_obj.guid}/stackato_drains", file_req_body, headers
          expect(last_response.status).to eq(400)
          expect(JSON.parse(last_response.body)['description']).to eq('Drain URI has an invalid scheme.')
        end

        it "should complain about a redis drain" do
          post "/v2/apps/#{app_obj.guid}/stackato_drains", redis_req_body, headers
          expect(last_response.status).to eq(400)
          expect(JSON.parse(last_response.body)['description']).to eq('Drain URI has an invalid scheme.')
        end

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
        expect(Kato::Config.get("logyard", "drains")).not_to be_empty
        delete "/v2/apps/#{app_obj.guid}/stackato_drains/#{drain_name}", {}, headers
        expect(last_response.status).to eq(204)
        expect(Kato::Config.get("logyard", "drains")).to be_empty
      end
    end

  end
end 


