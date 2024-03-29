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
        docker_image: docker_image,
        package_hash: package_hash,
        buildpack: buildpack,
        custom_buildpacks_enabled?: custom_buildpacks_enabled?,
        buildpack_specified?: false,
        diego?: false,
        "last_stager_response=".to_sym => nil
      )
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
    end
  end
end
