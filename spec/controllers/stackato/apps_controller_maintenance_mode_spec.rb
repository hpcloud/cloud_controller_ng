require "spec_helper"
require "stackato/spec_helper"

module VCAP::CloudController
  describe VCAP::CloudController::AppsController, type: :controller do
    before { configure_stacks }
    include_examples "uaa authenticated api", path: "/v2/apps"
    include_examples "querying objects", path: "/v2/apps", model: App, queryable_attributes: %w(name)
    include_examples "enumerating objects", path: "/v2/apps", model: App
    include_examples "reading a valid object", path: "/v2/apps", model: App, basic_attributes: %w(name space_guid stack_guid)
    include_examples "operations on an invalid object", path: "/v2/apps"
    include_examples "creating and updating", path: "/v2/apps", model: App,
                     required_attributes: %w(name space_guid),
                     unique_attributes: %w(name space_guid)
    include_examples "deleting a valid object", path: "/v2/apps", model: App, one_to_many_collection_ids: {
      :service_bindings => lambda { |app|
        service_instance = ManagedServiceInstance.make(
          :space => app.space
        )
        ServiceBinding.make(
          :app => app,
          :service_instance => service_instance
        )
      },
      :events => lambda { |app|
        AppEvent.make(:app => app)
      }
    }, :excluded => [ :events ]

    include_examples "collection operations", path: "/v2/apps", model: App,
      one_to_many_collection_ids: {
        service_bindings: lambda { |app|
          service_instance = ManagedServiceInstance.make(space: app.space)
          ServiceBinding.make(app: app, service_instance: service_instance)
        }
      },
      many_to_one_collection_ids: {
        space: lambda { |app| Space.make },
        stack: lambda { |app| Stack.make },
      },
      many_to_many_collection_ids: {
        routes: lambda { |app|
          domain = PrivateDomain.make(owning_organization: app.space.organization)
          Route.make(domain: domain, space: app.space)
        }
      }
      before(:all) do
        Kato::Config.set('cloud_controller_ng', '/maintenance_mode', true)
      end

    let(:app_event_repository) { CloudController::DependencyLocator.instance.app_event_repository }

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
          expect { create_app }.to raise_error(Errors::StackatoMaintenanceModeEnabled)
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
            expect { update_app }.to raise_error(Errors::StackatoMaintenanceModeEnabled)
          end
        end
      end

      describe "update app debug in maintenance mode" do
        context "set debug" do
          let(:update_hash) do
            {"debug" => "run"}
          end

          it "should work" do
            expect { update_app }.to raise_error(Errors::StackatoMaintenanceModeEnabled)
          end

        end

        context "change debug" do
          let(:app_obj) { AppFactory.make(:debug => "run") }

          let(:update_hash) do
            {"debug" => "suspend"}
          end

          it "should fail when in maintenance mode" do
            expect { update_app }.to raise_error(Errors::StackatoMaintenanceModeEnabled)
          end
        end

        context "reset debug" do
          let(:app_obj) { AppFactory.make(:debug => "run") }

          let(:update_hash) do
            {"debug" => "none"}
          end

          it "should fail when in maintenance mode" do
            expect { update_app }.to raise_error(Errors::StackatoMaintenanceModeEnabled)
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

      context "should fail" do
        let(:app_obj) { AppFactory.make }

        it "should delete the app" do
          expect { delete_app }.to raise_error(Errors::StackatoMaintenanceModeEnabled)
        end
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
          received_app = nil

          AppObserver.should_receive(:stage_app) do |app|
            received_app = app
            AppStagerTask::Response.new({})
          end
          
          def stage_app
            put "/v2/apps/#{app_obj.guid}", Yajl::Encoder.encode(:state => "STARTED"), json_headers(admin_headers)
          end

          expect { stage_app }.to raise_error(Errors::StackatoMaintenanceModeEnabled)
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

        DeaClient.should_receive(:update_uris).with(an_instance_of(VCAP::CloudController::App)) do |app|
          expect(app.uris).to include("app.jesse.cloud")
        end
        
        def add_route(route)
          put(
          @app_url,
          AppsController::UpdateMessage.new(
            :route_guids => [route.guid],
          ).encode,
          json_headers(@headers_for_user)
          )
        end
        expect { add_route(route) }.to raise_error(Errors::StackatoMaintenanceModeEnabled)
      end
    end
  end
end
