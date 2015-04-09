require 'spec_helper'
require 'stackato/spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoAppStoreControllerController, type: :controller do

    before do
      stub_appstore
    end

    describe 'POST /v2/appstore' do

      let(:space)     { Space.make }
      # let(:user)      { make_user_for_space(space) }
      # let(:headers)   { headers_for(user) }
      let(:req_body)  { 
        { :space_guid => space.guid, 
          :app_name => "test-app"
        }
      }

      it 'should create an app in the appstore' do
        post "/v2/appstore", MultiJson.dump(req_body), admin_headers
        expect(last_response.status).to eq(200)
      end
    end

    describe 'PUT /v2/appstore/:app_guid' do
      
      let(:app_obj)   { AppFactory.make }
      let(:space)     { app_obj.space }
      # let(:user)      { make_user_for_space(space) }
      # let(:headers)   { headers_for(user) }
      let(:req_body)  { 
        { :space_guid => space.guid, 
          :app_name => app_obj.name,
          :from => "https://github.com/as/test-app"
        }
      }

      it 'should deploy an app in the appstore' do
        put "/v2/appstore/#{app_obj.guid}", MultiJson.dump(req_body), admin_headers
        expect(last_response.status).to eq(200)
      end
    end

  end
end