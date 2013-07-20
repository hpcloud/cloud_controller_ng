require File.expand_path("../spec_helper", __FILE__)

module VCAP::CloudController
  describe Session do
    before { reset_database }

    let(:admin_user) { Models::User.make :admin => true }

    describe "POST /v2/sessions" do
      context "when a pubkey and an app is given" do
        let!(:some_app) { Models::App.make :guid => "some-app-guid" }

        context "and the app exists" do
          it "returns 201 Created" do
            post "/v2/sessions",
              '{"public_key":"some pubkey","app_guid":"some-app-guid"}',
              json_headers(headers_for(admin_user))

            last_response.status.should == 201
          end

          it "creates the session" do
            expect {
              post "/v2/sessions",
                '{"public_key":"some pubkey","app_guid":"some-app-guid"}',
                json_headers(headers_for(admin_user))

              response = Yajl::Parser.parse(last_response.body)
              guid = response["metadata"]["guid"]

              session = Models::Session.find(:guid => guid)
              expect(session.public_key).to eq("some pubkey")
              expect(session.app_guid).to eq("some-app-guid")
            }.to change {
              Models::Session.all.size
            }.by(1)
          end
        end

        context "and the app is not found" do
          before { some_app.destroy }

          it "returns HTTP status 400" do
            post "/v2/sessions",
              '{"public_key":"some pubkey","app_guid":"some-bogus-app-guid"}',
              json_headers(headers_for(admin_user))

            last_response.status.should == 400
          end
        end

        context "when a non-string public key is given" do
          it "returns a 400-level error code" do
            post "/v2/sessions",
              '{"public_key":42,"app_guid":"some-app-guid"}',
              json_headers(headers_for(admin_user))

            last_response.status.should == 400
          end
        end
      end

      context "and an app is NOT given" do
        it "returns a 400-level error code" do
          post "/v2/sessions",
            '{"public_key":"some pubkey"}',
            json_headers(headers_for(admin_user))

          last_response.status.should == 400
        end
      end

      context "when a pubkey is NOT given" do
        it "returns a 400-level error code" do
          post "/v2/sessions",
            '{"app_guid":"some-app-guid"}',
            json_headers(headers_for(admin_user))

          last_response.status.should == 400
        end
      end
    end

    describe "GET /v2/sessions" do
      before do
        @user_a = Models::User.make
        @user_b = Models::User.make

        @org_a = Models::Organization.make
        @org_b = Models::Organization.make

        @space_a = Models::Space.make :organization => @org_a
        @space_b = Models::Space.make :organization => @org_b

        @org_a.add_user(@user_a)
        @org_b.add_user(@user_b)

        @space_a.add_developer(@user_a)
        @space_b.add_developer(@user_b)

        @app_a = Models::App.make :space => @space_a
        @app_b = Models::App.make :space => @space_b

        @session_a = Models::Session.make :app => @app_a
        @session_b = Models::Session.make :app => @app_b
      end

      it "includes only sessions from apps visible to the user" do
        get "/v2/sessions", {}, headers_for(@user_a)

        parsed_body = Yajl::Parser.parse(last_response.body)
        parsed_body["total_results"].should == 1
      end

      describe "GET /v2/sessions/:guid" do
        context "when the guid is valid" do
          context "and the session is visible to the user" do
            it "returns the correct session" do
              get "/v2/sessions/#{@session_a.guid}", {},
                headers_for(@user_a)

              last_response.status.should == 200

              parsed_body = Yajl::Parser.parse(last_response.body)
              expect(parsed_body["entity"]["public_key"]).to eq(@session_a.public_key)
              expect(parsed_body["entity"]["app_guid"]).to eq(@session_a.app_guid)
            end
          end

          context "and the session is NOT visible to the user" do
            it "returns a 404 error" do
              get "/v2/sessions/#{@session_a.guid}", {},
                headers_for(@user_b)

              last_response.status.should == 403
            end
          end
        end

        context "when the guid is invalid" do
          it "returns a 404 error" do
            get "/v2/sessions/some-bogus-guid", {},
              headers_for(admin_user)

            last_response.status.should == 404
          end
        end
      end
    end

    describe "DELETE /v2/sessions/:guid" do
      before do
        @org = Models::Organization.make
        @space = Models::Space.make :organization => @org

        @admin = Models::User.make :admin => true
        @org_manager = Models::User.make
        @space_manager = Models::User.make
        @space_developer = Models::User.make
        @space_auditor = Models::User.make

        [ @org_manager, @space_manager, @space_developer,
          @space_auditor
        ].each do |user|
          @org.add_user(user)
        end

        @org.add_manager(@org_manager)
        @space.add_manager(@space_manager)
        @space.add_developer(@space_developer)
        @space.add_auditor(@space_auditor)

        @app = Models::App.make :space => @space
        @session = Models::Session.make :app => @app
      end

      def self.it_returns_status_code(code)
        it "returns status code #{code}" do
          delete "/v2/sessions/#{@session.guid}", {},
            headers_for(visiting_user)

          last_response.status.should == code
        end
      end

      def self.it_deletes_the_session
        it "deletes the session" do
          expect {
            delete "/v2/sessions/#{@session.guid}", {},
              headers_for(visiting_user)
          }.to change {
            Models::Session.find(:guid => @session.guid)
          }.to(nil)
        end
      end

      def self.it_does_not_delete_the_session
        it "does not delete the session" do
          expect {
            delete "/v2/sessions/#{@session.guid}", {}
            headers_for(visiting_user)
          }.to_not change {
            Models::Session.count
          }.by(-1)
        end
      end

      context "if there is no user logged in" do
        let(:visiting_user) { nil }
        it_returns_status_code 401
        it_does_not_delete_the_session
      end

      context "if the user is an admin" do
        let(:visiting_user) { @admin }
        it_returns_status_code 204
        it_deletes_the_session
      end

      context "if the user is an Organization Manager" do
        let(:visiting_user) { @org_manager }
        it_returns_status_code 403
        it_does_not_delete_the_session
      end

      context "if the user is a Space Manager" do
        let(:visiting_user) { @space_manager }
        it_returns_status_code 403
        it_does_not_delete_the_session
      end

      context "if the user is a Space Developer" do
        let(:visiting_user) { @space_developer }
        it_returns_status_code 204
        it_deletes_the_session
      end

      context "if the user is a Space Auditor" do
        let(:visiting_user) { @space_auditor }
        it_returns_status_code 403
        it_does_not_delete_the_session
      end
    end
  end
end
