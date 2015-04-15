require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoRolesController, type: :controller do

    describe "GET /v2/stackato/stats/collectd" do
      it "should return stats from a stackato node" do
        get "/v2/stackato/stats/collectd", {}, admin_headers
        puts last_response.inspect
      end
    end

  end
end