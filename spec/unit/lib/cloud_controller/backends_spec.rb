require "spec_helper"

module VCAP::CloudController
  describe Backends do
    let(:config) do
      {
        diego: "fake-diego-config"
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

    let(:blobstore_url_generator) do
      instance_double(CloudController::Blobstore::UrlGenerator)
    end

    let(:messenger) do
      instance_double(Diego::Messenger)
    end

    let(:app) do
      instance_double(App)
    end

    subject(:backends) do
      Backends.new(config, message_bus, dea_pool, stager_pool)
    end

    before do
      allow(CloudController::DependencyLocator.instance).to receive(:diego_messenger).and_return(messenger)
      allow(Dea::Backend).to receive(:new).and_call_original
      allow(Diego::Backend).to receive(:new).and_call_original
      allow(Diego::Messenger).to receive(:new).and_call_original
    end

    describe "#find_one_to_stage" do
      subject(:backend) do
        backends.find_one_to_stage(app)
      end

      context "when the app is configured to stage on Diego" do
        before do
          allow(app).to receive(:stage_with_diego?).and_return(true)
        end

        it "finds a Diego::Backend" do
          expect(backend).to be_a(Diego::Backend)
        end

        it "instantiates the backend with the correct dependencies" do
          backend
          expect(Diego::Backend).to have_received(:new).with(app, messenger)
        end
      end

      context "when the app is not configured to stage on Diego" do
        before do
          allow(app).to receive(:stage_with_diego?).and_return(false)
        end

        it "finds a DEA::Backend" do
          expect(backend).to be_a(Dea::Backend)
        end

        it "instantiates the backend with the correct dependencies" do
          backend
          expect(Dea::Backend).to have_received(:new).with(app, config, message_bus, dea_pool, stager_pool)
        end
      end
    end

    describe "#find_one_to_run" do
      subject(:backend) do
        backends.find_one_to_run(app)
      end

      context "when the app is configured to run on Diego" do
        before do
          allow(app).to receive(:run_with_diego?).and_return(true)
        end

        it "finds a Diego::Backend" do
          expect(backend).to be_a(Diego::Backend)
        end

        it "instantiates the backend with the correct dependencies" do
          backend
          expect(Diego::Backend).to have_received(:new).with(app, messenger)
        end
      end

      context "when the app is not configured to run on Diego" do
        before do
          allow(app).to receive(:run_with_diego?).and_return(false)
        end

        it "finds a DEA::Backend" do
          expect(backend).to be_a(Dea::Backend)
        end

        it "instantiates the backend with the correct dependencies" do
          backend
          expect(Dea::Backend).to have_received(:new).with(app, config, message_bus, dea_pool, stager_pool)
        end
      end
    end
  end
end
