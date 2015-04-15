require 'spec_helper'
require 'stackato/spec_helper'

module VCAP::CloudController
	describe VCAP::CloudController::StackatoAppLogsController, type: :controller do

		let(:app_obj)   { AppFactory.make }
		let(:developer) { make_developer_for_space(app_obj.space) }
		let(:headers)   { headers_for(developer) }

		describe "GET /v2/apps/:id/stackato_logs" do
			it "should show stackato logs for the app" do
				get  "/v2/apps/#{app_obj.guid}/stackato_logs", {}, headers
				# get  "/v2/stackato/info", {}, headers
				puts last_response.inspect
				expect(last_response.status).to eq(200)
			end
		end

	end
end	