require "spec_helper"

module VCAP::CloudController
  describe VCAP::CloudController::StagerPool do
    let(:message_bus) { CfMessageBus::MockMessageBus.new }
    let(:staging_advertise_msg) do
      {
          "id" => "staging-id",
          "stacks" => ["stack-name"],
          "available_memory" => 1024,
          "placement_properties" => {
            "zone" => "default",
            "zones" => ["default", "zone_cf"],
            "availability_zone" => "default",
          },
      }
    end

    subject { StagerPool.new(config, message_bus) }

    describe "#register_subscriptions" do
      it "finds advertised stagers" do
        subject.register_subscriptions
        message_bus.publish("staging.advertise", staging_advertise_msg)
        subject.find_stager("stack-name", 0, "default").should == "staging-id"
      end
    end

    describe "#find_stager" do
      describe "stager availability" do
        it "raises if there are no stagers with that stack" do
          subject.process_advertise_message(staging_advertise_msg)
          expect { subject.find_stager("unknown-stack-name", 0, "default") }.to raise_error(Errors::StackNotFound)
        end

        it "only finds registered stagers" do
          expect { subject.find_stager("stack-name", 0) }.to raise_error(Errors::StackNotFound)
          subject.process_advertise_message(staging_advertise_msg)
          subject.find_stager("stack-name", 0, "default").should == "staging-id"
        end
      end

      describe "staging advertisement expiration" do
        it "purges expired DEAs" do
          Timecop.freeze do
            subject.process_advertise_message(staging_advertise_msg)

            Timecop.travel(10)
            subject.find_stager("stack-name", 1024, "default").should == "staging-id"

            Timecop.travel(1)
            subject.find_stager("stack-name", 1024, "default").should be_nil
          end
        end
      end

      describe "memory capacity" do
        it "only finds stagers that can satisfy memory request" do
          subject.process_advertise_message(staging_advertise_msg)
          subject.find_stager("stack-name", 1025, "default").should be_nil
          subject.find_stager("stack-name", 1024, "default").should == "staging-id"
        end

        it "samples out of the top 5 stagers with enough memory" do
          (0..9).to_a.shuffle.each do |i|
            subject.process_advertise_message(
              "id" => "staging-id-#{i}",
              "stacks" => ["stack-name"],
              "available_memory" => 1024 * i,
            )
          end

          correct_stagers = (5..9).map { |i| "staging-id-#{i}" }

          10.times do
            expect(correct_stagers).to include(subject.find_stager("stack-name", 1024, "default"))
          end
        end
      end

      describe "stack availability" do
        it "only finds deas that can satisfy stack request" do
          subject.process_advertise_message(staging_advertise_msg)
          expect { subject.find_stager("unknown-stack-name", 0, "default") }.to raise_error(Errors::StackNotFound)
          subject.find_stager("stack-name", 0, "default").should == "staging-id"
        end
      end
    end
  end
end
