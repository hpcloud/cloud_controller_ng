require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoAppStoresController, type: :controller do

    let(:user)      { User.make }
    let(:headers)   { headers_for(user) }
    let(:store_req) { 
      { :name => "test-apps", 
        :content_url => "http://get.stackato.com/store/3.4/test-apps.yaml",
        :enabled => true,
        :verify_ssl => true
      }
    }

    describe 'for appstore' do

      describe 'GET /v2/stackato/app_stores' do
        it 'should query the app store' do
          get "/v2/stackato/app_stores", {}, headers
          expect(last_response.status).to eq(200)
          expect(decoded_response['total_results']).to be >= 0
        end
      end

      describe 'POST /v2/stackato/app_stores' do
        after {Kato::Config.del("cloud_controller_ng", "app_store/stores/#{store_req[:name]}")}
        it 'should add new appstore' do
          post  "/v2/stackato/app_stores", MultiJson.dump(store_req), admin_headers
          expect(last_response.status).to eq(201)
          expect(decoded_response['metadata']['name']).to eq(store_req[:name])
        end
      end
    end

    describe 'for a given store' do
      before(:each) { Kato::Config.set("cloud_controller_ng", "app_store/stores/#{store_req[:name]}", store_req.select{|k,v| k != :name}) }
      after(:each)  { Kato::Config.del("cloud_controller_ng", "app_store/stores/#{store_req[:name]}") }

      describe 'GET /v2/stackato/app_stores/:store_name' do
        it 'should get store configuration' do
          get "/v2/stackato/app_stores/#{store_req[:name]}", {}, headers
          expect(last_response.status).to eq(200)
          expect(decoded_response['metadata']['name']).to eq(store_req[:name])
        end
      end

       describe 'PUT /v2/stackato/app_stores/:store_name' do
        it 'should update store configuration' do
          put "/v2/stackato/app_stores/#{store_req[:name]}", MultiJson.dump({:verify_ssl => false}), admin_headers
          expect(last_response.status).to eq(200)
          expect(decoded_response['metadata']['name']).to eq(store_req[:name])
          expect(decoded_response['metadata']['verify_ssl']).to be_falsey
        end
      end

      describe 'DELETE /v2/stackato/app_stores/:store_name' do
        it 'should delete the store with the given name' do
          delete "/v2/stackato/app_stores/#{store_req[:name]}", {}, admin_headers
          expect(last_response.status).to eq(204)
        end
      end
    end

  end
end
