require "spec_helper"

module VCAP::CloudController
  module Jobs::Services
    describe ServiceInstanceUnbind do
      let(:client) { instance_double('VCAP::Services::ServiceBrokers::V2::Client') }
      let(:service_instance_guid) { 'fake-instance-guid' }
      let(:app_guid) { 'fake-app-guid' }
      let(:binding_guid) { 'fake-binding-guid' }

      let(:binding) { instance_double('VCAP::CloudController::ServiceBinding') }
      before do
        allow(VCAP::CloudController::ServiceBinding).to receive(:new).and_return(binding)
      end

      let(:name) { 'fake-name' }
      subject(:job) { VCAP::CloudController::Jobs::Services::ServiceInstanceUnbind.new(name, {}, binding_guid, service_instance_guid, app_guid) }

      describe '#perform' do
        before do
          allow(client).to receive(:unbind).with(binding)
          allow(VCAP::Services::ServiceBrokers::V2::Client).to receive(:new).and_return(client)
        end

        it 'unbinds the binding' do
          job.perform

          expect(client).to have_received(:unbind).with(binding)
        end
      end

      describe '#job_name_in_configuration' do
        it 'returns the name of the job' do
          expect(job.job_name_in_configuration).to eq(:service_instance_unbind)
        end
      end

      describe '#max_attempts' do
        it 'returns 3' do
          expect(job.max_attempts).to eq 3
        end
      end
    end
  end
end
