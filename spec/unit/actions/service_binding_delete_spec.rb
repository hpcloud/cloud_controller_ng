require 'spec_helper'
require 'actions/service_binding_delete'
require 'actions/deletion_errors'

module VCAP::CloudController
  describe ServiceBindingDelete do
    subject(:service_binding_delete) { ServiceBindingDelete.new }

    describe '#delete' do
      let!(:service_binding_1) { ServiceBinding.make }
      let!(:service_binding_2) { ServiceBinding.make }
      let!(:service_binding_dataset) { ServiceBinding.dataset }
      let(:user) { User.make }
      let(:user_email) { 'user@example.com' }

      before do
        stub_unbind(service_binding_1)
        stub_unbind(service_binding_2)
      end

      it 'deletes the service bindings' do
        service_binding_delete.delete(service_binding_dataset)

        expect { service_binding_1.refresh }.to raise_error Sequel::Error, 'Record not found'
        expect { service_binding_2.refresh }.to raise_error Sequel::Error, 'Record not found'
      end

      context 'when one binding deletion fails' do
        let(:service_binding_3) { ServiceBinding.make }

        before do
          stub_unbind(service_binding_1)
          stub_unbind(service_binding_2, status: 500)
          stub_unbind(service_binding_3)
        end

        it 'deletes all other bindings' do
          service_binding_delete.delete(service_binding_dataset)

          expect { service_binding_1.refresh }.to raise_error Sequel::Error, 'Record not found'
          expect { service_binding_2.refresh }.not_to raise_error
          expect { service_binding_3.refresh }.to raise_error Sequel::Error, 'Record not found'
        end

        it 'returns all of the errors caught' do
          errors = service_binding_delete.delete(service_binding_dataset)
          expect(errors[0]).to be_instance_of(VCAP::Services::ServiceBrokers::V2::Errors::ServiceBrokerBadResponse)
        end
      end

      describe 'locking service instances while binding deletes' do
        describe 'restoring the last operation' do
          context 'when the service instance has a last operation' do
            before do
              last_operation = ServiceInstanceOperation.make(type: 'create', state: 'succeeded')
              service_binding_1.service_instance.service_instance_operation = last_operation
              service_binding_1.service_instance.save
            end

            context 'when the delete succeeds' do
              it 'restores the last operation' do
                service_instance = service_binding_1.service_instance

                service_binding_delete.delete(service_binding_dataset)

                last_operation = service_instance.reload.last_operation
                expect(last_operation.type).to eq('create')
                expect(last_operation.state).to eq('succeeded')
              end
            end
            context 'when the delete fails' do
              before do
                stub_unbind(service_binding_1, status: 500)
              end
              it 'restores the last operation' do
                service_instance = service_binding_1.service_instance

                service_binding_delete.delete(service_binding_dataset)

                last_operation = service_instance.reload.last_operation
                expect(last_operation.type).to eq('create')
                expect(last_operation.state).to eq('succeeded')
              end
            end
          end

          context 'when the service instance does not have an operation in progress' do
            before do
              service_binding_1.service_instance.service_instance_operation = nil
              service_binding_1.service_instance.save
            end

            context 'when the delete succeeds' do
              it 'restores the last operation' do
                service_instance = service_binding_1.service_instance

                service_binding_delete.delete(service_binding_dataset)

                last_operation = service_instance.reload.last_operation
                expect(last_operation).to be_nil
              end
            end
            context 'when the delete fails' do
              before do
                stub_unbind(service_binding_1, status: 500)
              end
              it 'restores the last operation' do
                service_instance = service_binding_1.service_instance

                service_binding_delete.delete(service_binding_dataset)

                last_operation = service_instance.reload.last_operation
                expect(last_operation).to be_nil
              end
            end
          end
        end
      end
    end
  end
end
