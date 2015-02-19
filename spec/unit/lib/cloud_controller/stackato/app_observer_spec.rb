require "spec_helper"

module VCAP::CloudController
  describe AppObserver do
    let(:message_bus) { CfMessageBus::MockMessageBus.new }
    let(:stager_pool) { double(:stager_pool, :reserve_app_memory => nil) }
    let(:dea_pool) { double(:dea_pool, :find_dea => "dea-id", :mark_app_started => nil,
                            :reserve_app_memory => nil) }
    let(:staging_timeout) { 320 }
    let(:config_hash) { { staging: { timeout_in_seconds: staging_timeout } } }
    let(:blobstore_url_generator) { double(:blobstore_url_generator, :droplet_download_url => "download-url") }
    let(:tps_reporter) { double(:tps_reporter) }
    let(:diego_messenger) { Diego::Messenger.new(config_hash, message_bus, blobstore_url_generator) }
    let(:health_manager_client) { CloudController::DependencyLocator.instance.health_manager_client }
    let(:backends) { StackatoBackends.new(config_hash, message_bus, dea_pool, stager_pool, health_manager_client) }

    before do
      allow(CloudController::DependencyLocator.instance).to receive(:diego_messenger).and_return(diego_messenger)
      Dea::Client.configure(config_hash, message_bus, dea_pool, stager_pool, blobstore_url_generator)
      AppObserver.configure(backends)
    end

    describe ".updated" do
      let(:package_hash) { "bar" }
      let(:environment_json) { {} }
      let(:started_instances) { 1 }
      let(:stager_task) { double(:stager_task) }

      let(:app) do
        app = VCAP::CloudController::App.make(
            last_stager_response: nil,
            instances:            1,
            package_hash:         package_hash,
            droplet_hash:         "initial-droplet-hash",
            name:                 "app-name"
        )
        allow(app).to receive(:environment_json) { environment_json }
        app
      end

      subject { AppObserver.updated(app) }
      
      describe "when the 'diego' flag is not set" do
        let(:config_hash) { { :diego => false } }

        before do
         allow(Dea::AppStagerTask).to receive(:new).
            with(config_hash,
                 message_bus,
                 app,
                 dea_pool,
                 stager_pool,
                 instance_of(CloudController::Blobstore::UrlGenerator),
         ).and_return(stager_task)

          allow(stager_task).to receive(:stage) do |&callback|
            allow(app).to receive(:droplet_hash) { "staged-droplet-hash" }
            callback.call(:started_instances => started_instances)
          end

          allow(app).to receive_messages(previous_changes: changes)

          allow(Dea::Client).to receive(:start)
          allow(Dea::Client).to receive(:stop)
          allow(Dea::Client).to receive(:change_running_instances)
        end

        context "when the desired instance count change" do
          context "when the app is started" do
            context "when the instance count change increases the number of instances" do
              let(:changes) { { :instances => [5, 8] } }

              before do
                allow(Dea::Client).to receive(:change_running_instances).and_call_original
                allow(app).to receive(:started?) { true }
              end
              context "when the app bits were changed as well" do
                before do
                  app.mark_for_restaging
                end

                let(:package_hash) { "something new" }

                it "should start more instances of the old version" do

                  expect(message_bus).to receive(:publish) { |subject, message|
                    if subject == "dea.dea-id.start"
                      expect(message).to include({
                                                     sha1: "initial-droplet-hash"
                                                 })
                    else
                      expect(subject).to eq("droplet.updated")
                    end
                  }.exactly(4).times.ordered
                  subject
                end
              end
            end
          end
        end
      end
    end
  end
end
