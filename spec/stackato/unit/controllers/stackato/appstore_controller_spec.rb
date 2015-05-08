require 'spec_helper'
require 'stackato/spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoAppStoreController, type: :controller do

    before do
      stub_appstore
    end
    
    def make_request(headers)
      post "/v2/appstore", MultiJson.dump(req_body), headers
    end

    describe 'POST /v2/appstore' do
        let(:space) { Space.make }
        let(:req_body) {
          { space_guid: space.guid, app_name: "testapp" }}

      context 'regular' do

        it 'should create an app in the appstore' do
          post "/v2/appstore", MultiJson.dump(req_body), admin_headers
          expect(last_response.status).to eq(200)
        end
      end
      
      context 'admin user' do
        
        it 'should allow admins to upload with app_bits_upload flag disabled' do
          FeatureFlag.make(name: 'app_bits_upload', enabled: false)
          FeatureFlag.make(name: 'route_creation', enabled: true)
          post "/v2/appstore", MultiJson.dump(req_body), admin_headers
          expect(last_response.status).to eq(200)
        end

        it 'should allow admins to upload with route_creation flag disabled' do
          FeatureFlag.make(name: 'app_bits_upload', enabled: true)
          FeatureFlag.make(name: 'route_creation', enabled: false)
          post "/v2/appstore", MultiJson.dump(req_body), admin_headers
          expect(last_response.status).to eq(200)
        end

        it 'should allow admins to upload with both flags enabled' do
          FeatureFlag.make(name: 'app_bits_upload', enabled: true)
          FeatureFlag.make(name: 'route_creation', enabled: true)
          post "/v2/appstore", MultiJson.dump(req_body), admin_headers
          expect(last_response.status).to eq(200)
        end
      end

      context 'non-admin user' do
        let(:user) { make_user_for_space(space) }
        let(:user_headers) { headers_for(user) }
        it "shouldn't allow non-admins to upload with app_bits_upload flag disabled" do
          FeatureFlag.make(name: 'app_bits_upload', enabled: false)
          FeatureFlag.make(name: 'route_creation', enabled: true)
          post "/v2/appstore", MultiJson.dump(req_body), user_headers
          expect(last_response.status).to eq(403)
          # Set symbolize_names to false because of yajl bug
          body = JSON.parse(last_response.body, symbolize_names: false)
          expect(body["description"]).to match(/because app_bits_upload is off\. Both/)
        end

        it "shouldn't allow non-admins to upload with route_creation flag disabled" do
          FeatureFlag.make(name: 'app_bits_upload', enabled: true)
          FeatureFlag.make(name: 'route_creation', enabled: false)
          post "/v2/appstore", MultiJson.dump(req_body), user_headers
          expect(last_response.status).to eq(403)
          body = JSON.parse(last_response.body, symbolize_names: false)
          expect(body["description"]).to match(/because route_creation is off\. Both/)
        end

        it "shouldn't allow non-admins to upload with both flags disabled" do
          FeatureFlag.make(name: 'app_bits_upload', enabled: false)
          FeatureFlag.make(name: 'route_creation', enabled: false)
          post "/v2/appstore", MultiJson.dump(req_body), user_headers
          expect(last_response.status).to eq(403)
          body = JSON.parse(last_response.body, symbolize_names: false)
          expect(body["description"]).to match(/because both app_bits_upload and route_creation are off\. Both/)
        end

        it 'should allow admins to upload with both flags enabled' do
          FeatureFlag.make(name: 'app_bits_upload', enabled: true)
          FeatureFlag.make(name: 'route_creation', enabled: true)
          post "/v2/appstore", MultiJson.dump(req_body), user_headers
          expect(last_response.status).to eq(200)
        end
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
