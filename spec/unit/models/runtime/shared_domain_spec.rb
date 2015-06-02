require "spec_helper"

module VCAP::CloudController
  describe SharedDomain, type: :model do
    subject { described_class.make name: "test.example.com" }

    it { is_expected.to have_timestamp_columns }

    describe "Serialization" do
      it { is_expected.to export_attributes :name }
      it { is_expected.to import_attributes :name }
    end

    describe "#as_summary_json" do
      it "returns a hash containing the guid and name" do
        expect(subject.as_summary_json).to eq(
                                             guid: subject.guid,
                                             name: "test.example.com")
      end
    end

    describe "#validate" do
      include_examples "domain validation"

      context "when the name is foo.com and bar.foo.com is a shared domain" do
        before do
          SharedDomain.make name: "bar.foo.com"
          subject.name = "foo.com"
        end

        it { is_expected.to be_valid }
      end          
    end

    describe "#destroy" do
      it "destroys the routes" do
        # Stackato's SSO feature perform scim requests on Route deletion - see the following commit for more details:
        # https://github.com/ActiveState/cloud_controller_ng/commit/93b29f7f0aa2e3088908ff44bf392910186b92b2
        allow_any_instance_of(VCAP::CloudController::Route).to receive(:delete_oauth_client).and_return nil
        route = Route.make(domain: subject)

        expect do
          subject.destroy
        end.to change { Route.where(:id => route.id).count }.by(-1)
      end
    end

    describe "addable_to_organization!" do
      it "does not raise error" do
        expect{subject.addable_to_organization!(Organization.new)}.to_not raise_error
      end
    end
  end
end
