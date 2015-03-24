require "spec_helper"

module VCAP::CloudController
  describe Runners do
    let(:config) do
      {
        diego: {
          running: 'optional',
          running: 'optional',
        },
        diego_docker: true,
        staging: {
          timeout_in_seconds: 90
        }
      }
    end

    let(:message_bus) do
      instance_double(CfMessageBus::MessageBus)
    end

    let(:dea_pool) do
      instance_double(Dea::Pool)
    end

    let(:stager_pool) do
      instance_double(Dea::StagerPool)
    end

    let(:package_hash) do
      'fake-package-hash'
    end

    let(:custom_buildpacks_enabled?) do
      true
    end

    let (:buildpack) do
      instance_double(AutoDetectionBuildpack,
        custom?: false
      )
    end

    let(:docker_image) do
      nil
    end

    let(:app) do
      instance_double(App,
        docker_image: docker_image,
        package_hash: package_hash,
        buildpack: buildpack,
        custom_buildpacks_enabled?: custom_buildpacks_enabled?,
        buildpack_specified?: false,
      )
    end

    subject(:runners) do
      Runners.new(config, message_bus, dea_pool, stager_pool)
    end

    def make_diego_app(options = {})
      AppFactory.make(options).tap do |app|
        app.environment_json = (app.environment_json || {}).merge("DIEGO_RUN_BETA" => "true")
        app.package_state = "STAGED"
        app.save
      end
    end

    def make_dea_app(options = {})
      AppFactory.make(options).tap do |app|
        app.package_state = "STAGED"
        app.save
      end
    end

    describe "#runner_for_app" do
      subject(:runner) do
        runners.runner_for_app(app)
      end

      context "when the app is configured to run on Diego" do
        before do
          allow(app).to receive(:run_with_diego?).and_return(true)
        end

        context 'when diego running is enabled' do
          it "finds a diego backend" do
            expect(runners).to receive(:diego_runner).with(app).and_call_original
            expect(runner).to be_a(Diego::Runner)
          end

          context 'when the app has a docker image' do
            let(:docker_image) {'foobar'}

            it "finds a diego backend" do
              expect(runners).to receive(:diego_runner).with(app).and_call_original
              expect(runner).to be_a(Diego::Runner)
            end
          end

          context 'when diego is disabled' do
            before do
              config[:diego][:running] = 'disabled'
            end

            it "finds a dea backend" do
              expect(runners).to receive(:dea_runner).with(app).and_call_original
              expect(runner).to be_a(Dea::Runner)
            end

          end

        end

        context "when the app is not configured to run on Diego" do
          before do
            allow(app).to receive(:run_with_diego?).and_return(false)
          end

          it "finds a DEA backend" do
            expect(runners).to receive(:dea_runner).with(app).and_call_original
            expect(runner).to be_a(Dea::Runner)
          end
        end
      end
    end

    describe "#run_with_diego?" do
      let(:diego_app) {make_diego_app}
      let(:dea_app) {make_dea_app}

      context "when diego is enabled" do
        it "returns true for a diego app" do
          expect(runners.run_with_diego?(diego_app)).to be_truthy
        end

        it "returns false for a dea app" do
          expect(runners.run_with_diego?(dea_app)).to be_falsey
        end
      end

      context "when diego is disabled" do
        before do
          config[:diego][:running] = 'disabled'
        end

        it "returns false for a diego app" do
          expect(runners.run_with_diego?(diego_app)).to be_falsey
        end

        it "returns false for a dea app" do
          expect(runners.run_with_diego?(dea_app)).to be_falsey
        end
      end
    end

    describe "#diego_apps" do
      before do
        allow(runners).to receive(:diego_running_disabled?).and_return(false)

        5.times do |i|
          app = make_diego_app(id: i+1, state: "STARTED")
          app.add_route(Route.make(space: app.space))
        end

        make_dea_app(id:99, state: "STARTED")
      end

      it "returns apps that have the desired data" do
        last_app = make_diego_app({
          "id" => 6,
          "state" => "STARTED",
          "package_hash" => "package-hash",
          "disk_quota" => 1_024,
          "package_state" => "STAGED",
          "environment_json" => {
            "env-key-3" => "env-value-3",
            "env-key-4" => "env-value-4",
          },
          "file_descriptors" => 16_384,
          "instances" => 4,
          "memory" => 1_024,
          "guid" => "app-guid-6",
          "command" => "start-command-6",
          "stack" => Stack.make(name: "stack-6"),
        })

        route1 = Route.make(
          space: last_app.space,
          host: "arsenio",
          domain: SharedDomain.make(name: "lo-mein.com"),
        )
        last_app.add_route(route1)

        route2 = Route.make(
          space: last_app.space,
          host: "conan",
          domain: SharedDomain.make(name: "doe-mane.com"),
        )
        last_app.add_route(route2)

        last_app.version = "app-version-6"
        last_app.save

        apps = runners.diego_apps(100, 0)

        expect(apps.count).to eq(6)

        expect(apps.last.to_json).to match_object(last_app.to_json)
      end

      it "respects the batch_size" do
        app_counts = [3, 5].map do |batch_size|
          runners.diego_apps(batch_size, 0).count
        end

        expect(app_counts).to eq([3, 5])
      end

      it "returns non-intersecting apps across subsequent batches" do
        first_batch = runners.diego_apps(3, 0)
        expect(first_batch.count).to eq(3)

        second_batch = runners.diego_apps(3, first_batch.last.id)
        expect(second_batch.count).to eq(2)

        expect(second_batch & first_batch).to eq([])
      end

      it "does not return unstaged apps" do
        unstaged_app = make_diego_app(id: 6, state: "STARTED")
        unstaged_app.package_state = "PENDING"
        unstaged_app.save

        batch = runners.diego_apps(100, 0)

        expect(batch).not_to include(unstaged_app)
      end

      it "does not return apps which aren't expected to be started" do
        stopped_app = make_diego_app(id: 6, state: "STOPPED")

        batch = runners.diego_apps(100, 0)

        expect(batch).not_to include(stopped_app)
      end

      it "does not return deleted apps" do
        deleted_app = make_diego_app(id: 6, state: "STARTED", deleted_at: DateTime.current)

        batch = runners.diego_apps(100, 0)

        expect(batch).not_to include(deleted_app)
      end

      it "only includes apps that have DIEGO_RUN_BETA set" do
        non_diego_app = make_diego_app(id: 6, state: "STARTED")
        non_diego_app.environment_json = {}
        non_diego_app.save

        batch = runners.diego_apps(100, 0)

        expect(batch).not_to include(non_diego_app)
      end

      it "loads all of the associations eagerly" do
        expect {
          runners.diego_apps(100, 0).each do |app|
            app.current_droplet
            app.space
            app.stack
            app.routes
            app.service_bindings
            app.routes.map { |route| route.domain }
          end
        }.to have_queried_db_times(/SELECT/, [
          :apps,
          :droplets,
          :spaces,
          :stacks,
          :routes,
          :service_bindings,
          :domain
        ].length)
      end

      context 'when diego running is disabled' do
        before do
          allow(runners).to receive(:diego_running_disabled?).and_return(true)
        end

        it 'returns no apps' do
          expect(runners.diego_apps(100, 0)).to be_empty()
        end
      end
    end

    describe "#dea_apps" do
      let!(:diego_app) {make_diego_app(id: 99, state: "STARTED")}

      before do
        allow(runners).to receive(:diego_running_optional?).and_return(true)

        5.times do |i|
          app = make_dea_app(id: i+1, state: "STARTED")
          app.add_route(Route.make(space: app.space))
        end
      end

      it "returns apps that have the desired data" do
        last_app = make_dea_app({
          "id" => 6,
          "state" => "STARTED",
          "package_hash" => "package-hash",
          "disk_quota" => 1_024,
          "package_state" => "STAGED",
          "environment_json" => {
            "env-key-3" => "env-value-3",
            "env-key-4" => "env-value-4",
          },
          "file_descriptors" => 16_384,
          "instances" => 4,
          "memory" => 1_024,
          "guid" => "app-guid-6",
          "command" => "start-command-6",
          "stack" => Stack.make(name: "stack-6"),
        })

        route1 = Route.make(
          space: last_app.space,
          host: "arsenio",
          domain: SharedDomain.make(name: "lo-mein.com"),
        )
        last_app.add_route(route1)

        route2 = Route.make(
          space: last_app.space,
          host: "conan",
          domain: SharedDomain.make(name: "doe-mane.com"),
        )
        last_app.add_route(route2)

        last_app.version = "app-version-6"
        last_app.save

        apps = runners.dea_apps(100, 0)

        expect(apps.count).to eq(6)

        expect(apps.last.to_json).to match_object(last_app.to_json)
      end

      it "respects the batch_size" do
        app_counts = [3, 5].map do |batch_size|
          runners.dea_apps(batch_size, 0).count
        end

        expect(app_counts).to eq([3, 5])
      end

      it "returns non-intersecting apps across subsequent batches" do
        first_batch = runners.dea_apps(3, 0)
        expect(first_batch.count).to eq(3)

        second_batch = runners.dea_apps(3, first_batch.last.id)
        expect(second_batch.count).to eq(2)

        expect(second_batch & first_batch).to eq([])
      end

      it "does not return deleted apps" do
        deleted_app = make_dea_app(id: 6, state: "STARTED", deleted_at: DateTime.current)

        batch = runners.dea_apps(100, 0)

        expect(batch).not_to include(deleted_app)
      end

      context 'when diego running is disabled' do
        before do
          config[:diego][:running] = 'disabled'
        end

        it 'returns all the apps' do
          apps = runners.dea_apps(100, 0)
          expect(apps.count).to eq(6)
          expect(apps).to include(diego_app)
        end
      end
    end
  end
end
