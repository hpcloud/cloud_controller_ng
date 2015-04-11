require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoRolesController, type: :controller do

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
      "{ \"127.0.0.1\": #{node_roles} }"
    end

    describe "GET /v2/stackato/cluster/roles" do
      it "should return the list of roles on a node" do
        allow(Kato::Config).to receive(:get).and_call_original
        allow(Kato::Config).to receive(:get).with("node").and_return(MultiJson.load(node_response))
        get "/v2/stackato/cluster/roles", {}, admin_headers
        expect(last_response.status).to eq(200)
        expect(decoded_response["available"]).to be
        expect(decoded_response["nodes"]).to be
        expect(decoded_response["required"]).to be
        expect(decoded_response["nodes"].size).to be 1
      end
    end

    context "when dealing with a given node" do

      let (:node_id) { "127.0.0.1" }

      before(:each) do
        allow(Kato::Config).to receive(:get).and_call_original
        allow(Kato::Config).to receive(:get).with("node", node_id).and_return(MultiJson.load(node_roles)) 
      end

      describe "GET /v2/stackato/cluster/roles/:node_id" do
        it "should return info on the node with the given id" do
          get "/v2/stackato/cluster/roles/#{node_id}", {}, admin_headers
          expect(last_response.status).to eq(200)
          expect(decoded_response.size).to be > 0
        end
      end

      describe "PUT /v2/stackato/cluster/roles/:node_id" do
        let (:new_node_roles) do
          ["base", "primary", "controller", "router", "dea", "postgresql", "redis", "filesystem"]
        end
        it "should update information on a node" do
          allow(Kato::Cluster::SSH).to receive(:authorize_key_pair_on_dea_node).and_return(true)
          allow(Kato::Cluster::SSH).to receive(:authorize_key_pair_on_frontend).and_return(true)
          put "/v2/stackato/cluster/roles/#{node_id}", MultiJson.dump(new_node_roles), admin_headers
          expect(last_response.status).to eq(204)
        end
      end

    end

  end
end