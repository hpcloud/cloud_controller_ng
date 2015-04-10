require 'spec_helper'
require 'kato/config'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoConfigController, type: :controller do


    describe "GET /v2/stackato/config/components" do
      it "should return the list of components" do
        get "/v2/stackato/config/components", {}, admin_headers
        expect(last_response.status).to eq(200)
        expect(decoded_response.size).to be > 0
        expect(decoded_response.map{|o| o['name']}).to include("cloud_controller_ng") 
      end
    end

    describe "GET /v2/stackato/config/components/:component_name" do
      let (:component_name) { "cloud_controller_ng" }
      it "should return info for component with name `component_name`" do
        get "/v2/stackato/config/components/#{component_name}", {}, admin_headers
        expect(last_response.status).to eq(200)
        expect(decoded_response["local_route"]).to eq("127.0.0.1")
        expect(decoded_response["port"]).to eq(8181)
      end
    end

    describe "PUT /v2/stackato/config/components/:component_name" do
      let (:component_name)  { "cloud_controller_ng" }
      let (:new_port_number) { 1234 }
      it "should update the config for component with name `component_name`" do
        pending "component config info needs fixing"
        put "/v2/stackato/config/components/#{component_name}", MultiJson.dump({:port => new_port_number}), admin_headers
        expect(last_response.status).to eq(204)
        expect(decoded_response["port"]).to eq(new_port_number)
      end
    end

    describe "GET /v2/stackato/config" do
      let (:component_name)  { "cloud_controller_ng" }
      it "should return the list of components" do
        get "/v2/stackato/config?name=#{component_name}", {}, admin_headers
        expect(last_response.status).to eq(200)
        expect(decoded_response["info"]).not_to be_empty
      end
    end

    describe "PUT /v2/stackato/config" do
      let (:component_name)  { "cloud_controller_ng" }
      it "should update configuration" do
        put "/v2/stackato/config?name=#{component_name}", MultiJson.dump({:maintenance_mode => true}), admin_headers
        expect(last_response.status).to eq(204)
      end
    end

  end
end