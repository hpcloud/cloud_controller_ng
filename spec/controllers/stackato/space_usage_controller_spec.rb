require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoSpaceUsageController, type: :controller do

    let(:app_obj) { AppFactory.make }
    let(:space)   { app_obj.space }

    describe "GET /v2/spaces/:id/usage" do
      it "should return information on a space with the given id" do
        get "/v2/spaces/#{space.guid}/usage", {}, admin_headers
        expect(decoded_response["usage"]["mem"]).to be 0
        expect(decoded_response["allocated"]["mem"]).to be > 0
      end
    end

  end
end