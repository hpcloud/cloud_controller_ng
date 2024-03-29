require 'spec_helper'

module VCAP::CloudController
  describe RackAppBuilder do
    subject(:builder) do
      RackAppBuilder.new
    end

    let(:use_nginx) { false }

    before do
      TestConfig.override({
        :nginx => {
          :use_nginx => use_nginx,
        },
        :logging => {
          # value taken from upstream config/cloud_controller.yml
          :file => "/tmp/cloud_controller.log"
        },
      })

      allow(Rack::CommonLogger).to receive(:new)
    end

    describe '#build' do
      context 'when nginx is disabled' do
        it 'uses Rack::CommonLogger' do
          builder.build(TestConfig.config).to_app
          expect(Rack::CommonLogger).to have_received(:new).with(anything, instance_of(File))
        end
      end

      context 'when nginx is enabled' do
        let(:use_nginx) { true }

        it 'does not use Rack::CommonLogger' do
          builder.build(TestConfig.config).to_app
          expect(Rack::CommonLogger).to_not have_received(:new)
        end
      end

      it 'returns a Rack application' do
        expect(builder.build(TestConfig.config)).to be_a(Rack::Builder)
        expect(builder.build(TestConfig.config)).to respond_to(:call)
      end
    end
  end
end
