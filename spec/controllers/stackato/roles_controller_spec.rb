require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoRolesController, type: :controller do

    let (:node_id) { "127.0.0.1" }

    let (:node_roles) do
      '{
          "roles": {
            "base": "START",
            "primary": "START",
            "controller": "START",
            "router": "START",
            "dea": "START",
            "postgresql": "START",
            "mysql": "START",
            "filesystem": "START"
          }
        }'
    end

    let (:node_response) do
      "{ \"#{node_id}\": #{node_roles} }"
    end

    describe "GET /v2/stackato/cluster/roles" do
      it "should return the list of roles on a node" do
        allow(Kato::Config).to receive(:get).and_call_original
        allow(Kato::Config).to receive(:get).with("node").and_return(MultiJson.load(node_response))
        get "/v2/stackato/cluster/roles", {}, admin_headers
        expect(last_response.status).to eq(200)
        expect(decoded_response["available"]).not_to be_nil
        expect(decoded_response["nodes"]).not_to be_nil
        expect(decoded_response["required"]).not_to be_nil
        expect(decoded_response["nodes"].size).to be 1
      end
    end

    context "when dealing with a given node" do

      before(:each) do
        allow(Kato::Config).to receive(:get).and_call_original
        allow(Kato::Config).to receive(:get).with("node", node_id).and_return(MultiJson.load(node_roles)) 
      end

      describe "GET /v2/stackato/cluster/roles/:node_id" do
        it "should return info on the node with the given id" do
          get "/v2/stackato/cluster/roles/#{node_id}", {}, admin_headers
          expect(last_response.status).to eq(200)
          expect(decoded_response.size).to be > 0
          expect(decoded_response).to include("base", "primary", "controller")
        end
      end

      describe "PUT /v2/stackato/cluster/roles/:node_id" do
        let (:new_node_roles) do
          ["base", "primary", "controller", "router", "dea", "postgresql", "redis", "filesystem"]
        end
        it "should update information the node with the given id" do
          allow(Kato::Cluster::SSH).to receive(:authorize_key_pair_on_dea_node).and_return(true)
          allow(Kato::Cluster::SSH).to receive(:authorize_key_pair_on_frontend).and_return(true)
          put "/v2/stackato/cluster/roles/#{node_id}", MultiJson.dump(new_node_roles), admin_headers
          # passing the controller to the original kato config to see if the change is applied.
          allow(Kato::Config).to receive(:get).with("node", node_id).and_call_original
          expect(Kato::Config.get("node", node_id)["roles"]).to include("primary", "controller")
          expect(Kato::Config.get("node", node_id)["roles"]).to include("redis")
          expect(Kato::Config.get("node", node_id)["roles"]).not_to include("mysql")
        end
      end

    end

  end
end