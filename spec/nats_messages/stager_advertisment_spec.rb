require "spec_helper"
require "cloud_controller/nats_messages/stager_advertisment"

describe StagerAdvertisement do
  let(:message) do
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

  subject(:ad) { StagerAdvertisement.new(message) }

  describe "#stager_id" do
    its(:stager_id) { should eq "staging-id" }
  end

  describe "#stats" do
    its(:stats) { should eq message }
  end

  describe "#available_memory" do
    its(:available_memory) { should eq 1024 }
  end

  describe "#expired?" do
    let(:now) { Time.now }
    context "when the time since the advertisment is greater than 10 seconds" do
      it "returns false" do
        Timecop.freeze now do
          ad
          Timecop.travel now + 11.seconds do
            expect(ad).to be_expired
          end
        end
      end
    end

    context "when the time since the advertisment is less than or equal to 10 seconds" do
      it "returns false" do
        Timecop.freeze now do
          ad
          Timecop.travel now + 10.seconds do
            expect(ad).to_not be_expired
          end
        end
      end
    end
  end

  describe "#meets_needs?" do
    context "when it has the memory" do
      let(:mem) { 512 }

      context "and it has the stack" do
        let(:stack) { "stack-name" }
        it { expect(ad.meets_needs?(mem, stack)).to be_true }
      end

      context "and it does not have the stack" do
        let(:stack) { "not-a-stack-name" }
        it { expect(ad.meets_needs?(mem, stack)).to be_false }
      end
    end

    context "when it does not have the memory" do
      let(:mem) { 2048 }

      context "and it has the stack" do
        let(:stack) { "stack-name" }
        it { expect(ad.meets_needs?(mem, stack)).to be_false }
      end

      context "and it does not have the stack" do
        let(:stack) { "not-a-stack-name" }
        it { expect(ad.meets_needs?(mem, stack)).to be_false }
      end
    end
  end

  describe "#has_sufficient_memory?" do
    context "when the stager does not have enough memory" do
      it "returns false" do
        expect(ad.has_sufficient_memory?(2048)).to be_false
      end
    end

    context "when the stager has enough memory" do
      it "returns false" do
        expect(ad.has_sufficient_memory?(512)).to be_true
      end
    end
  end

  describe "#has_stack?" do
    context "when the stager has the stack" do
      it "returns false" do
        expect(ad.has_stack?("stack-name")).to be_true
      end
    end

    context "when the stager does not have the stack" do
      it "returns false" do
        expect(ad.has_stack?("not-a-stack-name")).to be_false
      end
    end
  end

  describe "#zone" do
    context "when the stager does not have the placement properties" do
      it "returns default zone" do
        expect(ad.zone).to eq "default"
      end
    end

    context "when the stager has empty placement properties" do
      before{ message["placement_properties"] = {} }

      it "returns default zone" do
        expect(ad.zone).to eq "default"
      end
    end

    context "when the stager has the placement properties with zone info" do
      before{ message["placement_properties"] = { "zone" => "zone_cf" } }

      it "returns the zone with name zone_cf" do
        expect(ad.zone).to eq "zone_cf"
      end
    end
  end
end