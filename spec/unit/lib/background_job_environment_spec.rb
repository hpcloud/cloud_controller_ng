require "spec_helper"

# Bug https://openproject.activestate.com/work_packages/301159 -- Do everything
# in one test to avoid deadlocking and running out of threads (??)

describe BackgroundJobEnvironment do
  let(:bg_config) { { db: "cc-db", logging: { level: 'debug2' } } }
  subject(:background_job_environment) { described_class.new(bg_config) }

  before do
    allow(Steno).to receive(:init)
  end

  describe "#setup_environment" do
    let(:message_bus) { double(:message_bus) }
    let(:message_bus_configurer) { double(MessageBus::Configurer, go: message_bus)}

    before do
      allow(MessageBus::Configurer).to receive(:new).and_return(message_bus_configurer)
      allow(VCAP::CloudController::DB).to receive(:load_models)
      allow(Thread).to receive(:new).and_yield
      allow(EM).to receive(:run).and_yield
    end

    it "loads models, configures components, and configures app observer" do
      expect(VCAP::CloudController::DB).to receive(:load_models)
      expect(VCAP::CloudController::Config).to receive(:configure_components)
      expect(VCAP::CloudController::AppObserver).to receive(:configure).with(
        instance_of(VCAP::CloudController::StackatoBackends)
      )
      background_job_environment.setup_environment
    end
  end
end

