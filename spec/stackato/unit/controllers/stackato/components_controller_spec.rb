require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoComponentsController, type: :controller do


    describe "GET /v2/stackato/components" do
      it "should get the list of components" do
        pending("We need to create fake nodes and add components to them for to test the api")
        fail
      end
    end

    describe "PUT /v2/stackato/components/:node_id/:component_name" do
      it "should add a component to a given node" do
        pending("We need to create fake nodes and add components to them for to test the api")
        fail
      end
    end

  end
end
