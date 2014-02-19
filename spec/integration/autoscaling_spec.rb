require "spec_helper"

module VCAP::CloudController
  describe "Cloud Controller", type: :integration do

    let(:message_bus) { CfMessageBus::MockMessageBus.new }
    let(:dea_client) { double("dea client", :message_bus => message_bus) }
    let(:health_manager_respondent) { HealthManagerRespondent.new(dea_client, message_bus) }

    before { health_manager_respondent.handle_requests }

    it "scales application instances" do
      app = AppFactory.make droplet_hash: nil, package_hash: nil
      app.should_receive(:lock!)
      app.should_receive(:update_from_hash).with({ data: "opaque" })
      AppsController.any_instance.should_receive(:find_guid_and_validate_access) { app }

      message_bus.publish('health_manager.adjust_instances',
                          { guid: "app-guid", data: "opaque" })
    end
  end
end
