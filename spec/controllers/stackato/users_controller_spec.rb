require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::StackatoUsersController, type: :controller do

    let(:user_id) { "some-id" }

    let(:user_info) do
      {
        :username    => "test_user",
        :password    => "test_password",
        :given_name  => "test_given_name",
        :family_name => "test_family_name",
        :email       => "test@stackato.com",
        :phone       => "+17787787788"
      }
    end

    describe "POST /v2/stackato/users" do

      context "when requesting user is not an admin" do
        let(:user)      { User.make }
        let(:headers)   { headers_for(user) }

        it "should reject user creation" do
          post "/v2/stackato/users", {}, headers
          expect(last_response.status).to eq(403)
          expect(last_response.body).to match(/NotAuthorized/)
        end
      end

      context "when requesting user is an admin" do

        context "when in maintenance mode" do
          before { TestConfig.override({:maintenance_mode => true})  }
          after  { TestConfig.override({:maintenance_mode => false}) }

          it "should reject adding new users" do
            post "/v2/stackato/users", {}, admin_headers
            expect(last_response.status).to eq(503)
            expect(last_response.body).to match(/Maintenance mode is enabled/)
          end
        end

        context "when not in maintenance_mode" do
          it "should create a normal user when user info is provided" do
            post "/v2/stackato/users", MultiJson.dump(user_info), admin_headers
            expect(last_response.status).to eq(201)
            expect(decoded_response["metadata"]["guid"]).to eq(user_id) #coming from the uaa_request stub
            expect(decoded_response["entity"]["spaces_url"]).to match(/some-id/) #coming from the uaa_request stub
            expect(decoded_response["entity"]["admin"]).to be_falsey
          end

          it "should create an admin user when the admin param is set to true" do
            user_info[:admin] = true
            post "/v2/stackato/users", MultiJson.dump(user_info), admin_headers
            expect(last_response.status).to eq(201)
            expect(decoded_response["metadata"]["guid"]).to eq(user_id) #coming from the uaa_request stub
            expect(decoded_response["entity"]["spaces_url"]).to match(/some-id/) #coming from the uaa_request stub
            expect(decoded_response["entity"]["admin"]).to be_truthy
          end
        end
      end
    end

    context "when there are users in the system" do

      let(:user) { User.make }

      describe "GET /v2/stackato/users" do
        context "when the requesting user is an admin" do
          it "shoudl return the list of users in all orgz" do
            get "/v2/stackato/users", MultiJson.dump({:q => "#{user.guid}"}), admin_headers
            pending ("needs fixing for proper json encoding")
            expect(last_response.status).to eq(200)
          end
        end
        
      end

      describe "PUT /v2/stackato/users/:id" do

        context "when in maintenance mode" do
          before { TestConfig.override({:maintenance_mode => true})  }
          after  { TestConfig.override({:maintenance_mode => false}) }

          it "should reject adding new users" do
            post "/v2/stackato/users", {}, admin_headers
            expect(last_response.status).to eq(503)
            expect(last_response.body).to match(/Maintenance mode is enabled/)
          end
        end

        it "should update user info" do
          user_info[:given_name]  = "updated_test_given_name"
          user_info[:family_name] = "updated_test_family_name"
          user_info[:admin] = true
          put "/v2/stackato/users/#{user.guid}", MultiJson.dump(user_info), admin_headers
          expect(last_response.status).to eq(200)
          expect(decoded_response["metadata"]["guid"]).not_to be_nil
          expect(decoded_response["entity"]["admin"]).to be_truthy
        end
        
      end

      describe "DELETE /v2/stackato/users/:id" do

        it "should delete the user" do
          delete "/v2/stackato/users/#{user.guid}", {}, admin_headers
          expect(last_response.status).to eq(200)
        end

      end


    end

  end
end