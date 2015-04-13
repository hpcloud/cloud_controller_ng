require 'spec_helper'
require 'handlers/processes_handler'

module VCAP::CloudController
  describe ProcessesController do
    let(:logger) { instance_double(Steno::Logger) }
    let(:processes_handler) { instance_double(ProcessesHandler) }
    let(:process_presenter) { double(:process_presenter) }
    let(:process_model) { AppFactory.make(app_guid: app_model.guid) }
    let(:app_model) { AppModel.make }
    let(:process) { ProcessMapper.map_model_to_domain(process_model) }
    let(:guid) { process.guid }
    let(:req_body) { '' }
    let(:expected_response) { 'process_response_body' }

    let(:processes_controller) do
      ProcessesController.new(
        {},
        logger,
        {},
        {},
        req_body,
        nil,
        {
          processes_handler: processes_handler,
          process_presenter: process_presenter
        },
      )
    end

    before do
      allow(logger).to receive(:debug)
      allow(process_presenter).to receive(:present_json).and_return(expected_response)
    end

    describe '#list' do
      let(:page) { 1 }
      let(:per_page) { 2 }
      let(:params) { { 'page' => page, 'per_page' => per_page } }
      let(:list_response) { 'list_response' }

      before do
        allow(process_presenter).to receive(:present_json_list).and_return(expected_response)
        allow(processes_handler).to receive(:list).and_return(list_response)
      end

      it 'returns 200 and lists the apps' do
        response_code, response_body = processes_controller.list

        expect(processes_handler).to have_received(:list)
        expect(process_presenter).to have_received(:present_json_list).with(list_response, '/v3/processes')
        expect(response_code).to eq(200)
        expect(response_body).to eq(expected_response)
      end
    end

    describe '#show' do
      before do
        allow(processes_handler).to receive(:show).and_return(process)
      end

      context 'when the process does not exist' do
        let(:guid) { 'ABC123' }
        before do
          allow(processes_handler).to receive(:show).and_return(nil)
        end

        it 'raises an ApiError with a 404 code' do
          expect {
            processes_controller.show(guid)
          }.to raise_error do |error|
            expect(error.name).to eq 'ResourceNotFound'
            expect(error.message).to eq 'Process not found'
            expect(error.response_code).to eq 404
          end
        end
      end

      it 'returns 200 OK' do
        response_code, _ = processes_controller.show(guid)
        expect(response_code).to eq(HTTP::OK)
      end

      it 'returns the process information' do
        _, response = processes_controller.show(guid)
        expect(response).to eq(expected_response)
      end
    end

    describe '#create' do
      let(:req_body) do
        {
          'name' => 'my-process',
          'memory' => 256,
          'instances' => 2,
          'disk_quota' => 1024,
          'space_guid' => Space.make.guid,
          'stack_guid' => Stack.make.guid,
          'app_guid' => app_model.guid,
        }.to_json
      end

      context 'when the user cannot create a process because they are unauthorized' do
        before do
          allow(processes_handler).to receive(:create).and_raise(ProcessesHandler::Unauthorized)
        end

        it 'returns a 403 NotAuthorized error' do
          expect {
            processes_controller.create
          }.to raise_error do |error|
            expect(error.name).to eq 'NotAuthorized'
            expect(error.response_code).to eq 403
          end
        end
      end

      context 'when the process cannot be created because it is invalid' do
        before do
          allow(processes_handler).to receive(:create).and_raise(ProcessesHandler::InvalidProcess)
        end

        it 'returns an UnprocessableEntity error' do
          expect {
            processes_controller.create
          }.to raise_error do |error|
            expect(error.name).to eq 'UnprocessableEntity'
            expect(error.response_code).to eq 422
          end
        end
      end

      context 'when the request body is invalid JSON' do
        let(:req_body) { '{ invalid_json }' }
        it 'returns an 400 Bad Request' do
          expect {
            processes_controller.create
          }.to raise_error do |error|
            expect(error.name).to eq 'MessageParseError'
            expect(error.response_code).to eq 400
          end
        end
      end

      context 'when a user can create a process' do
        before do
          allow(processes_handler).to receive(:create).and_return(process)
        end

        it 'returns a 201 Created response' do
          response_code, _ = processes_controller.create
          expect(response_code).to eq(HTTP::CREATED)
        end

        it 'returns the process information' do
          _, response = processes_controller.create
          expect(response).to eq(expected_response)
        end
      end
    end

    describe '#update' do
      let(:new_space) { Space.make }
      let(:req_body) do
        {
          'memory' => 256,
          'instances' => 2,
          'disk_quota' => 1024,
          'space_guid' => new_space.guid,
          'stack_guid' => Stack.make.guid,
        }.to_json
      end

      before do
        allow(processes_handler).to receive(:update).and_return(process)
      end

      it 'returns a 200 OK response' do
        response_code, _ = processes_controller.update(guid)
        expect(response_code).to eq(HTTP::OK)
      end

      it 'returns the process information' do
        _, response = processes_controller.update(guid)
        expect(response).to eq(expected_response)
      end

      context 'when the user cannot update to the desired state' do
        let(:desired_process) { AppProcess.new({ space_guid: new_space.guid }) }

        before do
          allow(processes_handler).to receive(:update).and_raise(ProcessesHandler::Unauthorized)
        end

        it 'returns a 403 NotAuthorized error' do
          expect {
            processes_controller.update(guid)
          }.to raise_error do |error|
            expect(error.name).to eq 'NotAuthorized'
            expect(error.response_code).to eq 403
          end
        end
      end

      context 'when the process does not exist' do
        before do
          allow(processes_handler).to receive(:update).and_return(nil)
        end

        it 'raises an ApiError with a 404 code' do
          expect {
            processes_controller.update(guid)
          }.to raise_error do |error|
            expect(error.name).to eq 'ResourceNotFound'
            expect(error.response_code).to eq 404
          end
        end
      end

      context 'when persisting the process fails because it is invalid due to an error' do
        let(:req_body) do
          {
            name: 'a-new-name'
          }.to_json
        end

        before do
          allow(processes_handler).to receive(:update).and_raise(ProcessesHandler::InvalidProcess)
        end

        it 'raises an UnprocessableEntity with a 422' do
          expect {
            processes_controller.update(guid)
          }.to raise_error do |error|
            expect(error.name).to eq 'UnprocessableEntity'
            expect(error.response_code).to eq 422
          end
        end
      end

      context 'when persisting the process fails because it is invalid due to validation' do
        let(:req_body) do
          {
            name: 'a-new-name'
          }.to_json
        end

        it 'raises an UnprocessableEntity with a 422' do
          expect {
            processes_controller.update(guid)
          }.to raise_error do |error|
            expect(error.name).to eq 'UnprocessableEntity'
            expect(error.response_code).to eq 422
          end
        end
      end

      context 'when the request body is invalid JSON' do
        let(:req_body) { '{ invalid_json }' }
        it 'returns an 400 Bad Request' do
          expect {
            processes_controller.update(guid)
          }.to raise_error do |error|
            expect(error.name).to eq 'MessageParseError'
            expect(error.response_code).to eq 400
          end
        end
      end
    end

    describe '#delete' do
      let(:space) { Space.make }
      let(:user) { User.make }
      let(:app_model) { AppModel.make(space_guid: space.guid) }
      let(:process) { AppFactory.make(app_guid: app_model.guid) }

      before do
        # stubbing the BaseController methods for now, this should probably be
        # injected into the packages controller
        allow(processes_controller).to receive(:current_user).and_return(user)
        allow(processes_controller).to receive(:check_write_permissions!)

        space.organization.add_user(user)
        space.add_developer(user)
      end

      it 'checks for write permissions' do
        processes_controller.delete(process.guid)
        expect(processes_controller).to have_received(:check_write_permissions!)
      end

      context 'when the process exists' do
        context 'when a user can access a process' do
          it 'returns a 204 NO CONTENT' do
            response_code, response = processes_controller.delete(process.guid)
            expect(response_code).to eq 204
            expect(response).to be_nil
          end
        end

        context 'when the user cannot access the process' do
          before do
            allow(processes_controller).to receive(:current_user).and_return(User.make)
          end

          it 'returns a 404 NotFound error' do
            expect {
              processes_controller.delete(process.guid)
            }.to raise_error do |error|
              expect(error.name).to eq 'ResourceNotFound'
              expect(error.response_code).to eq 404
            end
          end
        end
      end

      context 'when the process does not exist' do
        it 'raises an ApiError with a 404 code' do
          expect {
            processes_controller.delete('bad_guid')
          }.to raise_error do |error|
            expect(error.name).to eq 'ResourceNotFound'
            expect(error.response_code).to eq 404
          end
        end
      end
    end
  end
end
