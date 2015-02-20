require "spec_helper"
require "cloud_controller/dependency_locator"

describe CloudController::DependencyLocator do
  subject(:locator) { CloudController::DependencyLocator.send(:new, config) }

  describe "#health_manager_client" do
    it "should return the HealthManagerClient" do
      expect(locator.health_manager_client).to be_an_instance_of(VCAP::CloudController::HealthManagerClient)
    end
  end
end
