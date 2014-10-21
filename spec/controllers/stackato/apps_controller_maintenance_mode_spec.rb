require "spec_helper"
require "stackato/spec_helper"

module VCAP::CloudController
  describe VCAP::CloudController::AppsController, type: :controller do
    before(:all) do
      Kato::Config.set('cloud_controller_ng', '/maintenance_mode', true)
    end

    after(:all) do
      Kato::Config.set('cloud_controller_ng', '/maintenance_mode', false)
    end

    describe "create app" do
      let(:space_guid) { Space.make.guid.to_s }
      let(:initial_hash) do
        {
          name: "maria",
          space_guid: space_guid
        }
      end

      let(:decoded_response) { Yajl::Parser.parse(last_response.body) }

      def create_app
        post "/v2/apps", Yajl::Encoder.encode(initial_hash), json_headers(admin_headers)
      end

      context "when in maintenance mode" do
        it "should fail when in maintenance mode" do
          create_app
          expect(last_response.status).to eq(503)
          expect(last_response.body).to match(/Maintenance mode is enabled/)
        end
      end
    end

    describe "update app" do
      let(:update_hash) { {} }

      let(:app_obj) { AppFactory.make(:detected_buildpack => "buildpack-name") }

      def update_app
        put "/v2/apps/#{app_obj.guid}", Yajl::Encoder.encode(update_hash), json_headers(admin_headers)
      end

      describe "update in maintenance mode" do
        context "should fail when in maintenance mode" do
          let(:update_hash) { {"health_check_timeout" => 80} }

          it "should set to provided value" do
            update_app
            expect(last_response.status).to eq(503)
            expect(last_response.body).to match(/Maintenance mode is enabled/)
          end
        end
      end

      describe "update app debug in maintenance mode" do
        context "set debug" do
          let(:update_hash) do
            {"debug" => "run"}
          end

          it "should work" do
            update_app
            expect(last_response.status).to eq(503)
            expect(last_response.body).to match(/Maintenance mode is enabled/)
          end

        end

        context "change debug" do
          let(:app_obj) { AppFactory.make(:debug => "run") }

          let(:update_hash) do
            {"debug" => "suspend"}
          end

          it "should fail when in maintenance mode" do
            update_app
            expect(last_response.status).to eq(503)
            expect(last_response.body).to match(/Maintenance mode is enabled/)
          end
        end

        context "reset debug" do
          let(:app_obj) { AppFactory.make(:debug => "run") }

          let(:update_hash) do
            {"debug" => "none"}
          end

          it "should fail when in maintenance mode" do
            update_app
            expect(last_response.status).to eq(503)
            expect(last_response.body).to match(/Maintenance mode is enabled/)
          end
        end
      end
    end

    describe "delete an app" do
      let(:app_obj) { AppFactory.make }

      let(:decoded_response) { Yajl::Parser.parse(last_response.body) }

      def delete_app
        delete "/v2/apps/#{app_obj.guid}", {}, json_headers(admin_headers)
      end

      it "should fail" do
        delete_app
        expect(last_response.status).to eq(503)
        expect(last_response.body).to match(/Maintenance mode is enabled/)
      end
    end

    describe "staging" do
      context "when app will be staged", non_transactional: true do
        let(:app_obj) do
          AppFactory.make(:package_hash => "abc", :state => "STOPPED",
                           :droplet_hash => nil, :package_state => "PENDING",
                           :instances => 1)
        end

        it "stages the app asynchronously" do
          def stage_app
            put "/v2/apps/#{app_obj.guid}", Yajl::Encoder.encode(:state => "STARTED"), json_headers(admin_headers)
          end

          stage_app
          expect(last_response.status).to eq(503)
          expect(last_response.body).to match(/Maintenance mode is enabled/)
        end
      end
    end

    describe "on route change" do
      let(:space) { Space.make }
      let(:domain) do
        PrivateDomain.make(name: "jesse.cloud", owning_organization: space.organization)
      end

      before do
        user = make_developer_for_space(space)
        # keeping the headers here so that it doesn't reset the global config...
        @headers_for_user = headers_for(user)
        @app = AppFactory.make(
          :space => space,
          :state => "STARTED",
          :package_hash => "abc",
          :droplet_hash => "def",
          :package_state => "STAGED",
        )
        @app_url = "/v2/apps/#{@app.guid}"
      end

      it "tells the dea client to update when we add one url through PUT /v2/apps/:guid" do
        route = domain.add_route(
          :host => "app",
          :space => space,
        )

        def add_route(route)
          put(
          @app_url,
          AppsController::UpdateMessage.new(
            :route_guids => [route.guid],
          ).encode,
          json_headers(@headers_for_user)
          )
        end
        add_route(route)
        expect(last_response.status).to eq(503)
        expect(last_response.body).to match(/Maintenance mode is enabled/)
      end
    end
  end
end
