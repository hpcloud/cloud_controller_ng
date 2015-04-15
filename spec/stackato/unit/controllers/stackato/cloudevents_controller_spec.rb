require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoCloudeventsController, type: :controller do

    let(:sample_events) do
      '[
          {
            "status":"die",
            "id":"91e57bf2bcf52d84eeb4ac1438f8bdb9b92a6b8c68b4459820cfa9ebc2098654",
            "from":"0.0.0.0:4569/stackato/stack-alsek:300379-add-custom-docker-registry",
            "time":1428709540
          },
          {
            "status":"kill",
            "id":"91e57bf2bcf52d84eeb4ac1438f8bdb9b92a6b8c68b4459820cfa9ebc2098654",
            "from":"0.0.0.0:4569/stackato/stack-alsek:300379-add-custom-docker-registry",
            "time":1428709540
          }
      ]'
    end    

    describe "GET /v2/stackato/cloudevents" do
      it "should provide a list of events" do
        allow_any_instance_of(StackatoCloudeventsController).to receive(:redis).and_return(MultiJson.load(sample_events))
        get "/v2/stackato/cloudevents", {}, admin_headers
        puts last_response.inspect
      end
    end

  end
end
