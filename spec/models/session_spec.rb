require File.expand_path("../spec_helper", __FILE__)

module VCAP::CloudController
  describe Models::Session do
    let(:app) { Models::App.make :name => "my app" }

    subject do
      Models::Session.make :public_key => "some fake pubkey",
        :app => app
    end

    it "has a public key" do
      expect(subject.public_key).to eq("some fake pubkey")
    end

    it "belongs to an application" do
      expect(subject.app.name).to eq("my app")
    end

    describe "#space" do
      it "returns the app's space, for use by permissions checks" do
        expect(subject.space).to eq(app.space)
      end
    end

    describe "#to_json" do
      it "serializes with public_key and app_guid entries" do
        expect(subject.to_json).to eq(%Q|{"public_key":"some fake pubkey","app_guid":"#{app.guid}"}|)
      end
    end

    describe "#update_from_json" do
      describe "updating public_key" do
        it "can be updated from JSON with a public_key" do
          expect {
            subject.update_from_json('{"public_key":"another fake pubkey"}')
          }.to change {
            subject.public_key
          }.from("some fake pubkey").to("another fake pubkey")
        end
      end

      describe "updating app_guid" do
        context "with a valid app" do
          let(:other_app) { Models::App.make }

          it "updates the relationship" do
            expect {
              subject.update_from_json(%Q|{"app_guid":"#{other_app.guid}"}|)
            }.to change {
              subject.app
            }.from(app).to(other_app)
          end
        end

        context "with an invalid app" do
          it "blows up" do
            pending "doesn't currently blow up :("

            expect {
              subject.update_from_json(%Q|{"app_guid":"bad_app_guid"}|)
            }.to raise_error
          end
        end
      end
    end

    describe "#after_commit" do
      let(:config_hash) { { :config => "hash" } }
      let(:message_bus) { CfMessageBus::MockMessageBus.new }
      let(:dea_pool) { double :dea_pool }

      before { DeaClient.configure(config_hash, message_bus, dea_pool) }

      it "sends ssh.start with the public key, the URI for the app's droplet" do
        Staging.stub(:droplet_download_uri).with(app) do
          "https://some-download-uri"
        end

        session = Models::Session.make :public_key => "some fake pubkey", :app => app

        message_bus.should have_published_with_message(
          "ssh.start",
          :session => session.guid,
          :public_key => session.public_key,
          :package => "https://some-download-uri")
      end
    end

    describe "#after_destroy_commit" do
      let(:config_hash) { { :config => "hash" } }
      let(:message_bus) { CfMessageBus::MockMessageBus.new }
      let(:dea_pool) { double :dea_pool }

      before { DeaClient.configure(config_hash, message_bus, dea_pool) }

      it "sends ssh.start with the public key, the URI for the app's droplet" do
        Staging.stub(:droplet_download_uri).with(app) do
          "https://some-download-uri"
        end

        session = Models::Session.make :public_key => "some fake pubkey", :app => app

        session.destroy

        message_bus.should have_published_with_message(
          "ssh.stop",
          :session => session.guid)
      end
    end
  end
end
