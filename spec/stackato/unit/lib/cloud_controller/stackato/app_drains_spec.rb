require 'spec_helper'
require 'stackato/spec_helper'

module VCAP::CloudController
  describe StackatoAppDrains do
    let(:logger) { double(Steno::Logger) }


    let(:app)       { AppFactory.make }
    let(:drain_name){ 'test_drain' }
    let(:drain_uri) { 'tcp://test.stackato.com' }


    before (:each) do
      allow(StackatoAppDrains).to receive(:sanitize_uri).and_call_original
      allow(StackatoAppDrains).to receive(:globally_unique_drain_id).and_call_original
      VCAP::CloudController::StackatoAppDrains.create(app, drain_name, drain_uri, nil)
    end

    after(:each) { StackatoAppDrains.delete_all(app) }

    describe "#validate_name" do
      it "should reject nil drain name" do
        expect { StackatoAppDrains.validate_name(nil) }.to raise_error(VCAP::Errors::ApiError)
      end

      it "should reject invalid names" do
        expect { StackatoAppDrains.validate_name("12345") }.to raise_error(VCAP::Errors::ApiError)
      end

      it "should reject drain names shorter than 4 chars" do
        expect { StackatoAppDrains.validate_name("n") }.to raise_error(VCAP::Errors::ApiError)
      end

      it "should reject drain names longer than 25 chars" do
        expect { StackatoAppDrains.validate_name("this-is-a-very-long-drain-message-to-be-rejected") }.to raise_error(VCAP::Errors::ApiError)
      end
    end

    describe "#sanitize_uri" do
      let(:http_drain_uri)      { 'http://test.stackato.com/' }
      let(:no_scheme_drain_uri) { 'test.stackato.com/' }
      let(:invalid_drain_port)  { 1234 }

      it "should only allow tcp and udp drain names" do
        expect { StackatoAppDrains.sanitize_uri(http_drain_uri) }.to raise_error(VCAP::Errors::ApiError)
      end

      it "should reject unacceptable ports" do
        expect { StackatoAppDrains.sanitize_uri("#{drain_uri}:#{invalid_drain_port}") }.to raise_error(VCAP::Errors::ApiError)
      end

      it "should uri without proper scheme" do
        expect { StackatoAppDrains.sanitize_uri(no_scheme_drain_uri) }.to raise_error(VCAP::Errors::ApiError)
      end

      it "should return a valid string with the drain name" do
        expect(StackatoAppDrains.sanitize_uri(drain_uri)).to match(/test/)
      end
    end

    describe "#create" do
      it "should create a drain with name and uri" do
        expect(StackatoAppDrains).to have_received(:sanitize_uri).with(drain_uri)
        expect(StackatoAppDrains).to have_received(:globally_unique_drain_id).with(app, drain_name)
        expect(Kato::Config.get("logyard", "drains").size).to be > 0
        expect(Kato::Config.get("logyard", "drains").keys.first).to match(/test_drain/)
      end
    end

    describe "#delete" do
      it "should delete a drain with the given name" do
        StackatoAppDrains.delete(app, drain_name)
        expect(Kato::Config.get("logyard", "drains").size).to be 0
      end
    end

    context "when there is multiple drains" do

      let(:drain_name_2){ 'test_drain_2' }
      let(:drain_uri_2) { 'tcp://test2.stackato.com/' }
      before do
        stub_logyard_request
        allow(StackatoAppDrains).to receive(:user_uri).and_call_original
        VCAP::CloudController::StackatoAppDrains.create(app, drain_name_2, drain_uri_2, nil)
      end

      describe "#app_drains_count" do
        it "should return the list of drains for an app" do
          expect(StackatoAppDrains.app_drains_count(app)).to be 2
        end
      end
      
      describe "#list" do
        it "should list all drains for a given app" do
          expect(StackatoAppDrains.list(app).size).to be 2
          expect(StackatoAppDrains).to have_received(:user_uri).with(StackatoAppDrains.globally_unique_drain_id(app, drain_name), anything)
        end
      end

      describe "#delete_all" do
        it "should delete all drains for a given app" do
          expect(Kato::Config.get("logyard", "drains").size).to be 2
          StackatoAppDrains.delete_all(app)
          expect(Kato::Config.get("logyard", "drains").size).to be 0
        end
      end
    end

  end
end
