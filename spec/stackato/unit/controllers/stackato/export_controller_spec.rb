require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoExportController, type: :controller do

    describe "GET /v2/stackato/export" do
      it "should export" do
        get "/v2/stackato/export", {}, admin_headers
        pending "needs to be revisited"
        fail
      end
    end

    describe "GET /v2/stackato/export_info" do
      it "should export" do
        get "/v2/stackato/export_info", {}, admin_headers
        expect(last_response.status).to eq(200)
        expect(decoded_response["export_available"]).to be_falsey
        expect(decoded_response["export_in_progress"]).to be_falsey
      end
    end

  end
end
