require 'spec_helper'

module VCAP::CloudController
  describe DropletsController do
    let(:logger) { instance_double(Steno::Logger) }
    let(:user) { User.make }
    let(:params) { {} }
    let(:droplets_handler) { double(:droplets_handler) }
    let(:droplet_presenter) { double(:droplet_presenter) }
    let(:membership) { double(:membership) }
    let(:req_body) { '{}' }

    let(:droplets_controller) do
      DropletsController.new(
        {},
        logger,
        {},
        params.stringify_keys,
        req_body,
        nil,
        {
          droplets_handler: droplets_handler,
          droplet_presenter: droplet_presenter,
        },
      )
    end

    before do
      allow(logger).to receive(:debug)
      allow(droplets_controller).to receive(:membership).and_return(membership)
      allow(membership).to receive(:has_any_roles?).and_return(true)
    end

    describe '#show' do
      context 'when the droplet does not exist' do
        before do
          allow(droplets_handler).to receive(:show).and_return(nil)
        end

        it 'returns a 404 Not Found' do
          expect {
            droplets_controller.show('non-existant')
          }.to raise_error do |error|
            expect(error.name).to eq 'ResourceNotFound'
            expect(error.response_code).to eq 404
          end
        end
      end

      context 'when the droplet exists' do
        let(:droplet) { DropletModel.make }
        let(:droplet_guid) { droplet.guid }

        context 'when a user can access a droplet' do
          let(:expected_response) { 'im a response' }

          before do
            allow(droplets_handler).to receive(:show).and_return(droplet)
            allow(droplet_presenter).to receive(:present_json).and_return(expected_response)
          end

          it 'returns a 200 OK and the droplet' do
            response_code, response = droplets_controller.show(droplet_guid)
            expect(response_code).to eq 200
            expect(response).to eq(expected_response)
          end
        end

        context 'when the user cannot access the droplet' do
          before do
            allow(droplets_handler).to receive(:show).and_raise(DropletsHandler::Unauthorized)
          end

          it 'returns a 403 NotAuthorized error' do
            expect {
              droplets_controller.show(droplet_guid)
            }.to raise_error do |error|
              expect(error.name).to eq 'NotAuthorized'
              expect(error.response_code).to eq 403
            end
          end
        end
      end
    end

    describe '#delete' do
      let(:space) { Space.make }
      let(:org) { space.organization }
      let(:app_model) { AppModel.make(space_guid: space.guid) }
      let(:droplet) { DropletModel.make(app_guid: app_model.guid) }

      before do
        # stubbing the BaseController methods for now, this should probably be
        # injected into the droplets controller
        allow(droplets_controller).to receive(:check_write_permissions!)
      end

      it 'checks for write permissions' do
        droplets_controller.delete(droplet.guid)
        expect(droplets_controller).to have_received(:check_write_permissions!)
      end

      it 'returns a 204 NO CONTENT' do
        response_code, response = droplets_controller.delete(droplet.guid)
        expect(response_code).to eq 204
        expect(response).to be_nil
      end

      it 'checks for the proper roles' do
        droplets_controller.delete(droplet.guid)

        expect(membership).to have_received(:has_any_roles?).at_least(1).times
        expect(membership).to have_received(:has_any_roles?).exactly(1).times.
          with([Membership::SPACE_DEVELOPER], space.guid)
      end

      context 'when the droplet does not exist' do
        before do
          allow(droplets_handler).to receive(:delete).and_return([])
        end

        it 'returns a 404 Not Found' do
          expect {
            droplets_controller.delete('non-existant')
          }.to raise_error do |error|
            expect(error.name).to eq 'ResourceNotFound'
            expect(error.response_code).to eq 404
          end
        end
      end

      context 'when the user cannot read the droplet' do
        before do
          allow(membership).to receive(:has_any_roles?).and_raise('incorrect args')
          allow(membership).to receive(:has_any_roles?).with(
            [Membership::SPACE_DEVELOPER,
             Membership::SPACE_MANAGER,
             Membership::SPACE_AUDITOR,
             Membership::ORG_MANAGER], space.guid, org.guid).and_return(false)
        end

        it 'returns a 404 ResourceNotFound error' do
          expect {
            droplets_controller.delete(droplet.guid)
          }.to raise_error do |error|
            expect(error.name).to eq 'ResourceNotFound'
            expect(error.response_code).to eq 404
          end
        end
      end

      context 'when the user can read but cannot write to the droplet' do
        before do
          allow(membership).to receive(:has_any_roles?).and_raise('incorrect args')
          allow(membership).to receive(:has_any_roles?).with(
            [Membership::SPACE_DEVELOPER,
             Membership::SPACE_MANAGER,
             Membership::SPACE_AUDITOR,
             Membership::ORG_MANAGER], space.guid, org.guid).
            and_return(true)
          allow(membership).to receive(:has_any_roles?).with([Membership::SPACE_DEVELOPER], space.guid).
            and_return(false)
        end

        it 'raises ApiError NotAuthorized' do
          expect {
            droplets_controller.delete(droplet.guid)
          }.to raise_error do |error|
            expect(error.name).to eq 'NotAuthorized'
            expect(error.response_code).to eq 403
          end
        end
      end
    end

    describe '#list' do
      let(:page) { 1 }
      let(:per_page) { 2 }
      let(:params) { { 'page' => page, 'per_page' => per_page } }
      let(:list_response) { 'list_response' }
      let(:expected_response) { 'im a response' }

      before do
        allow(droplet_presenter).to receive(:present_json_list).and_return(expected_response)
        allow(droplets_handler).to receive(:list).and_return(list_response)
      end

      it 'returns 200 and lists the apps' do
        response_code, response_body = droplets_controller.list

        expect(droplets_handler).to have_received(:list)
        expect(droplet_presenter).to have_received(:present_json_list).with(list_response, '/v3/droplets')
        expect(response_code).to eq(200)
        expect(response_body).to eq(expected_response)
      end
    end
  end
end
