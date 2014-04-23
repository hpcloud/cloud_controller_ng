require "spec_helper"

module VCAP::CloudController
  # Test license handling
  describe VCAP::CloudController::LegacyInfo, type: :controller do
    describe "license checks" do
      let(:current_user) { make_user_with_default_space(:admin => true) }
      let(:headers) { headers_for(current_user) }
      let(:license) { Kato::Config.get('cluster', 'license') }
      let(:no_license_required) { Kato::Config.get('cluster', 'no_license_required') }
      let(:free_license) { Kato::Config.get('cluster', 'free_license') }
      let(:license_checking) { Kato::Config.get("cluster", "license_checking") }
      
      after(:each) do
        if !license.nil?
            Kato::Config.set('cluster', 'license', license)
        end
        if !license_checking.nil?
          Kato::Config.set("cluster", "license_checking", license_checking)
        end
        if !no_license_required.nil?
          Kato::Config.set("cluster", "no_license_required", no_license_required)
        end
        if !free_license.nil?
          Kato::Config.set("cluster", "free_license", free_license)
        end
      end
      describe "for a user with a full license" do
        [true, nil].each do | license_checking_status|
          before do
            Kato::Config.set('cluster', 'license', {
              user: "Flip <flip@example.com",
              organization: "mervish.com",
              serial: "ABCD1234",
              memory_limit: 25,
              expiration: "2019-12-31",
            })
            Kato::Config.set("cluster", "license_checking", true)
          end
          it "should return full license info" do
            get "/info", {}, headers
            expect(last_response.status).to be(200)
            hash = Yajl::Parser.parse(last_response.body)
            has_license = Kato::Config.get("cluster", "license_checking")
            expect(has_license).to be(true)
            hash.should have_key("license")
            license = hash["license"]
            license.should_not have_key("user")
            license.should have_key("organization")
            license.should have_key("memory_limit")
            expect(license["memory_limit"]).to be(25)
            license.should have_key("memory_in_use")
            license.should_not have_key("expiration")
          end
        end
      end
      
      describe "for a user with no license" do
        before do
          Kato::Config.del('cluster', 'license')
          Kato::Config.set("cluster", "license_checking", true)
          Kato::Config.set("cluster", "no_license_required", 4)
          Kato::Config.set("cluster", "free_license", 20)
        end
        it "should return empty license info" do
          get "/info", {}, headers
          expect(last_response.status).to be(200)
          hash = Yajl::Parser.parse(last_response.body)
          has_license = Kato::Config.get("cluster", "license_checking")
          expect(has_license).to be(true)
          hash.should have_key("license")
          license = hash["license"]
          license.should_not have_key("user")
          license.should_not have_key("organization")
          license.should have_key("memory_limit")
          license.should have_key("memory_in_use")
          license.should_not have_key("expiration")
        end
      end
      
      describe "with license-checking off" do
        before do
          Kato::Config.set('cluster', 'license', {
              user: "Flip <flip@example.com",
              organization: "mervish.com",
              serial: "ABCD1234",
              memory_limit: 27,
              expiration: "2019-12-31",
          })
          Kato::Config.set("cluster", "license_checking", false)
        end
        it "should return no license info" do
          get "/info", {}, headers
          expect(last_response.status).to be(200)
          hash = Yajl::Parser.parse(last_response.body)
          hash.should_not have_key("license")
        end
      end
      
    end
  end
end
