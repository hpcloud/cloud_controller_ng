# encoding: utf-8
require 'spec_helper'

module VCAP::CloudController
  describe App, type: :model do
    let(:org) { Organization.make }
    let(:space) { Space.make(organization: org) }

    let(:domain) { PrivateDomain.make(owning_organization: org) }

    let(:route) { Route.make(domain: domain, space: space) }

    before do
      VCAP::CloudController::Seeds.create_seed_stacks
    end

    describe 'Validations' do
      let(:app) { AppFactory.make }

      describe 'instances' do
        let(:scaler) { double(:scaler, scale: nil) }
        it 'broadcasts app-update after instances change' do
          allow(AppObserver).to receive(:react_to_state_change).and_return(nil)
          allow_any_instance_of(StackatoRunners).to receive(:runner_for_app).and_return(scaler)
          expect_any_instance_of(StackatoRunners).to receive(:broadcast_app_updated).once.with(app)
          app.start!
          app.save
          app.after_commit
          app.instances = app.instances + 1
          app.save
          app.after_commit
          expect(app).to be_valid
        end
      end
    end
  end
end
