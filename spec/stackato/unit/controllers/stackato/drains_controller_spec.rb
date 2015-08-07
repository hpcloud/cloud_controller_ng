require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoDrainsController, type: :controller do

    describe "GET /v2/drains" do    
      # return all drains info
      let (:drain_stat_msg) { '{"builtin.apptail":{"192.168.4.189":{"name":"RUNNING","rev":"3"}},"builtin.cloudevents":{"192.168.4.189":{"name":"RUNNING","rev":"3"}},"builtin.katohistory":{"192.168.4.189":{"name":"RUNNING","rev":"3"}},"builtin.timeline":{"192.168.4.189":{"name":"RUNNING","rev":"20"}},"test":{"192.168.4.189":{"name":"RUNNING","rev":"3"}}}' }
      let (:drain_list_msg) { ["builtin.apptail redis://stackato-core:6464/?filter=apptail\u0026limit=400","builtin.cloudevents redis://stackato-core:6464/?filter=event\u0026limit=256\u0026key=cloud_events","builtin.katohistory redis://stackato-core:6464/?filter=event.kato_action\u0026limit=256\u0026key=kato_history","builtin.timeline tcp://127.0.0.1:9026?filter=event\u0026format=json","test redis://stackato-core:6464/?filter=event?filter=systail\u0026format=systail"] }

      it "should return the list of all drains" do
        allow(Kato::Log::Drains).to receive(:list_drains).and_return(drain_list_msg)
        allow(Kato::Log::Drains).to receive(:status).and_return(MultiJson.load(drain_stat_msg))
        get "/v2/drains", {}, admin_headers
        expect(last_response.status).to eq(200)
        expect(decoded_response["total_results"]).to be > 0
      end
    end

    describe "POST /v2/drains" do
      let (:new_drain) do
        {
          :name => "test_drain",
          :uri  => "redis://stackato-core:6464/?filter=apptail\u0026limit=400"
        }
      end
      let (:drain_add_msg) { '{"name":"test_drain","uri":"redis://stackato-core:6464/?filter=apptail\u0026limit=400?"}' }

      it "should add a new drain to the list" do
        allow(Kato::Log::Drains).to receive(:add_drain).and_return(MultiJson.load(drain_add_msg))
        post "/v2/drains", MultiJson.dump(new_drain), admin_headers
        expect(last_response.status).to eq(201)
      end

      context "when in maintenance mode" do
        before { TestConfig.override({:maintenance_mode => true})  }
        after  { TestConfig.override({:maintenance_mode => false}) }

        it "should reject adding new drains" do
          post "/v2/drains", MultiJson.dump(new_drain), admin_headers
          expect(last_response.status).to eq(503)
          expect(last_response.body).to match(/Maintenance mode is enabled/)
        end
      end
    end

    describe "GET /v2/drains/:name" do
      # return info on the drain with the given name
      let (:drain_stat_msg) { '{"builtin.apptail":{"192.168.4.189":{"name":"RUNNING","rev":"3"}}}' }
      let (:drain_uri)      { 'redis://stackato-core:6464/?filter=apptail\u0026limit=400' }      
      let (:drain_name)     { 'builtin.apptail' }

      it "should get information on a given drain" do
        allow(Kato::Log::Drains).to receive(:drain_uri).and_return(drain_uri)
        allow(Kato::Log::Drains).to receive(:status).and_return(MultiJson.load(drain_stat_msg))
        get "/v2/drains/#{drain_name}", {}, admin_headers
        expect(last_response.status).to eq(200)
        expect(decoded_response["entity"]["name"]).to eq(drain_name)
        expect(decoded_response["entity"]["uri"] ).to eq(drain_uri)
      end
    end

    describe "DELETE /v2/drains/:name" do
      let (:drain_name)     { 'builtin.apptail' }

      it "should delete a drain with the given name" do
        allow(Kato::Log::Drains).to receive(:run_logyard_remote).and_return([200, "{}"])
        delete "/v2/drains/#{drain_name}", {}, admin_headers
        expect(last_response.status).to eq(200)
      end

      context "when in maintenance mode" do
        before { TestConfig.override({:maintenance_mode => true})  }
        after  { TestConfig.override({:maintenance_mode => false}) }

        it "should reject deleting a drain" do
          delete "/v2/drains/#{drain_name}", {}, admin_headers
          expect(last_response.status).to eq(503)
          expect(last_response.body).to match(/Maintenance mode is enabled/)
        end
      end
    end

  end
end
