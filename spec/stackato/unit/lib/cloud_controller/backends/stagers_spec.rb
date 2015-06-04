require 'spec_helper'

module VCAP::CloudController
  describe StackatoStagers do
    let(:config) { TestConfig.config }

    let(:message_bus)  { instance_double(CfMessageBus::MessageBus) }
    let(:dea_pool)     { instance_double(Dea::Pool) }
    let(:stager_pool)  { instance_double(Dea::StagerPool, find_stager:1 ) }
    let(:stack)        { instance_double(Stack, name:"yapper") }
    let(:runners)      { Runners.new(config, message_bus, dea_pool, stager_pool) }
    let(:package_hash) { 'fake-package-hash' }
    let(:buildpack)    { instance_double(AutoDetectionBuildpack, custom?: false) }
    let(:docker_image) { nil }
    let(:custom_buildpacks_enabled?) { true }

    let(:app) do
      instance_double(App,
        name: "Chemda",
        docker_image: docker_image,
        package_hash: package_hash,
        buildpack: buildpack,
        custom_buildpacks_enabled?: custom_buildpacks_enabled?,
        buildpack_specified?: false,
        diego?: false,
        "last_stager_response=".to_sym => nil
      )
    end
    let(:fake_logger) do
      double(info: :info_logger, warn: :warn_logger)
    end

    subject(:stagers) do
      StackatoStagers.new(config, message_bus, dea_pool, stager_pool, runners)
    end
    describe '#stager_for_app' do
      let(:stager) do
        stagers.stager_for_app(app)
      end

      context 'when the App is staging to the DEA' do
        before do
          allow_any_instance_of(Dea::StackatoAppStagerTask).to receive(:stage).and_yield(:staging_result)
          allow_any_instance_of(Dea::Runner).to receive(:start)
        end

        it 'finds a DEA/Stackato backend' do
          expect(stager).to be_a(Dea::StackatoStager)
        end
        it 'can should stage an app without throwing an error' do
          expect {
            stager.stage_app
          }.to_not raise_error
        end
      end
      context "when the App can't be staged to the DEA" do
        before do
          allow_any_instance_of(Dea::StackatoAppStagerTask).to receive(:stage).and_yield(:staging_result)
          allow_any_instance_of(Dea::Runner).to receive(:start)
          allow(app).to receive("needs_staging?".to_sym).and_return(true)
          allow(subject).to receive(:stage_app).with(app).and_raise(Errors::ApiError.new_from_details("StagingError"))
        end
        it "logs a problem" do
          c = config
          c[:staging] ||= {}
          num_tries = 3
          c[:staging][:num_repeated_tries] = num_tries
          c[:staging][:time_between_tries] = 0.1
          # Here it makes sense that the logger is tested as we have a bug against it.
          # It also captures the behavior of failing every time, and never succeeding.
          expect(subject).to receive(:logger).and_return(fake_logger).exactly(num_tries).times
          expect(fake_logger).to receive(:warn).exactly(num_tries).times
          expect(fake_logger).to receive(:info).exactly(0).times
          expect {
            subject.stage_if_needed(app) do
              expect("In callback").to eq("shouldn't be called")
            end
          }.to raise_error(Errors::ApiError)
          # Here's a case where we want to verify that the logger is called.
        end
      end
    end
  end
end
