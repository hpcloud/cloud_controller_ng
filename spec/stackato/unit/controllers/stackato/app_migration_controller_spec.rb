require 'spec_helper'
require 'stackato/spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::AppMigrationController, type: :controller do

    let(:app_obj)   { AppFactory.make }
    let(:new_space) { Space.make :organization => app_obj.organization }
    let(:req_body)  { MultiJson.dump({ :space_guid => new_space.guid }) }

    describe "POST /v2/stackato/apps/:id/migrate" do
      it "should migrate the app to another space" do
        post "/v2/stackato/apps/#{app_obj.guid}/migrate", req_body, json_headers(admin_headers)
        expect(last_response.status).to eq(200)
      end
    end

  end
end