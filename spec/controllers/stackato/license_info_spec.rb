require "spec_helper"
require 'digest/sha1'
require 'yajl'

module VCAP::CloudController
  # Test license handling
  OneMB = 2 ** 20
  def hashed_license_from_hash(license_hash)
    lic_parts = [:organization, :serial, :type, :memory_limit,
                 :expiration].map{|k| license_hash[k]}.insert(0, '1').join(",")
    lic_parts + "," + Digest::SHA1.hexdigest(lic_parts)
  end
  if Kato::Config.get("cluster", "license_urls/get_free_license").nil?
    Kato::Config.set("cluster", "license_urls/get_free_license",
                     Kato::Constants::LICENSE_URL_FREE_LICENSE_URL)
  end
  if Kato::Config.get("cluster", "license_urls/upgrade_license").nil?
    Kato::Config.set("cluster", "license_urls/upgrade_license",
                     Kato::Constants::LICENSE_URL_UPGRADE_LICENSE_URL)
  end
  if Kato::Config.get("cluster", "license_urls/purchase_license").nil?
    Kato::Config.set("cluster", "license_urls/purchase_license",
                     Kato::Constants::LICENSE_URL_PURCHASE_LICENSE_URL)
  end
  
  describe VCAP::CloudController::LegacyInfo, type: :controller do
    let(:current_user) { make_user_with_default_space(:admin => true) }
    let(:headers) { headers_for(current_user) }
    describe "license checks" do
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
            new_license = {
              user: "Flip <flip@example.com",
              organization: "example.com",
              serial: "ABCD1234",
              type: "paid",
              memory_limit: 25,
              expiration: "2099-12-31",
            }
            Kato::Config.set('cluster', 'license', hashed_license_from_hash(new_license), :force => true)
            Kato::Config.set("cluster", "license_checking", true)
          end
          it "should return full license info" do
            get "/info", {}, headers
            expect(last_response.status).to eq(200)
            hash = Yajl::Parser.parse(last_response.body)
            has_license = Kato::Config.get("cluster", "license_checking")
            expect(has_license).to eq(true)
            hash.should have_key("license")
            license = hash["license"]
            license.should_not have_key("user")
            license.should have_key("organization")
            license.should have_key("memory_limit")
            expect(license["memory_limit"]).to eq(25)
            license.should have_key("memory_in_use")
            license.should_not have_key("expiration")
            license.should have_key("state")
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
          expect(last_response.status).to eq(200)
          hash = Yajl::Parser.parse(last_response.body)
          has_license = Kato::Config.get("cluster", "license_checking")
          expect(has_license).to eq(true)
          hash.should have_key("license")
          license = hash["license"]
          license.should_not have_key("user")
          license.should_not have_key("organization")
          license.should have_key("memory_limit")
          license.should have_key("memory_in_use")
          license.should have_key("state")
          license.should_not have_key("expiration")
        end
      end
      
      describe "with license-checking off" do
        before do
          new_license = {
            user: "Flip <flip@example.com",
            organization: "example.com",
            serial: "ABCD1234",
            type: "paid",
            memory_limit: 27,
            expiration: "2098-12-31",
          }
          Kato::Config.set('cluster', 'license', hashed_license_from_hash(new_license), :force => true)
          Kato::Config.set("cluster", "license_checking", false)
        end
        it "should return no license info" do
          get "/info", {}, headers
          expect(last_response.status).to eq(200)
          hash = Yajl::Parser.parse(last_response.body)
          hash.should_not have_key("license")
        end
      end

      describe "for a compliant license" do
        before do
          new_license = {
            user: "Flip <flip@example.com",
            organization: "example.com",
            serial: "ABCD1234",
            type: "paid",
            memory_limit: 25,
            expiration: "2099-12-31",
          }
          Kato::Config.set('cluster', 'license', hashed_license_from_hash(new_license), :force => true)
          Kato::Config.set("cluster", "license_checking", true)
          Kato::Config.set("cluster", "memory", {
            "192.168.68.82" => 8 * OneMB,
            "192.168.68.98" => 8 * OneMB,
            "192.168.68.65" => 9 * OneMB})
        end
        it "should be compliant" do
          get "/info", {}, headers
          expect(last_response.status).to eq(200)
          hash = Yajl::Parser.parse(last_response.body)
          license = hash["license"]
          expect(license["state"]).to eq("HAS_LICENSE_COMPLIANT")
          license.should_not have_key("url")
        end
      end

      describe "for a non-compliant license" do
        before do
          new_license = {
            user: "Flip <flip@example.com",
            organization: "example.com",
            serial: "ABCD1234",
            type: "paid",
            memory_limit: 25,
            expiration: "2099-12-31",
          }
          Kato::Config.set('cluster', 'license', hashed_license_from_hash(new_license), :force => true)
          Kato::Config.set("cluster", "license_checking", true)
          Kato::Config.set("cluster", "memory", {
            "192.168.68.82" => 8 * OneMB,
            "192.168.68.98" => 8 * OneMB,
            "192.168.68.65" => 11 * OneMB})
        end
        it "should offer to upgrade the license" do
          get "/info", {}, headers
          expect(last_response.status).to eq(200)
          hash = Yajl::Parser.parse(last_response.body)
          license = hash["license"]
          expect(license["state"]).to eq("HAS_LICENSE_NONCOMPLIANT")
          expect(license["url"]).to eq(Kato::Config.get("cluster", "license_urls/upgrade_license"))
        end
      end

      describe "for a compliant non-license" do
        before do
          Kato::Config.del('cluster', 'license')
          Kato::Config.set("cluster", "license_checking", true)
          Kato::Config.set("cluster", "memory", {
            "192.168.68.82" => 2 * OneMB,
            "192.168.68.65" => 2 * OneMB})
        end
        it "should be compliant" do
          get "/info", {}, headers
          expect(last_response.status).to eq(200)
          hash = Yajl::Parser.parse(last_response.body)
          license = hash["license"]
          expect(license["state"]).to eq("NO_LICENSE_COMPLIANT")
          license.should_not have_key("url")
        end
      end

      describe "for a non-compliant non-license within free bounds" do
        before do
          Kato::Config.del('cluster', 'license')
          Kato::Config.set("cluster", "license_checking", true)
          Kato::Config.set("cluster", "memory", {
            "192.168.68.82" => 5 * OneMB,
            "192.168.68.98" => 6 * OneMB,
            "192.168.68.65" => 9 * OneMB})
        end
        it "should be non-compliant but qualifies for free license" do
          get "/info", {}, headers
          expect(last_response.status).to eq(200)
          hash = Yajl::Parser.parse(last_response.body)
          license = hash["license"]
          expect(license["state"]).to eq("NO_LICENSE_NONCOMPLIANT_UNDER_FREE_MEMORY")
          expect(license["url"]).to eq(Kato::Config.get("cluster", "license_urls/get_free_license"))
        end
      end

      describe "for a non-compliant non-license exceeding free bounds" do
        before do
          Kato::Config.del('cluster', 'license')
          Kato::Config.set("cluster", "license_checking", true)
          Kato::Config.set("cluster", "memory", {
            "192.168.68.82" => 5 * OneMB,
            "192.168.68.98" => 8 * OneMB,
            "192.168.68.65" => 9 * OneMB})
        end
        it "should be non-compliant and needs a paid license" do
          get "/info", {}, headers
          expect(last_response.status).to eq(200)
          hash = Yajl::Parser.parse(last_response.body)
          license = hash["license"]
          expect(license["state"]).to eq("NO_LICENSE_NONCOMPLIANT_OVER_FREE_MEMORY")
          expect(license["url"]).to eq(Kato::Config.get("cluster", "license_urls/purchase_license"))
        end
      end

      describe 'for first run setup' do
        before do
          Kato::Config.set("cluster", "no_license_required", 42)
          Kato::Config.set('cluster', 'license', 'type: microcloud', force: true)
          Kato::Config.set("cluster", "license_checking", true)
        end
        it "should have the correct memory limit" do
          get "/info", {}, headers
          expect(last_response.status).to eq(200)
          hash = Yajl::Parser.parse(last_response.body)
          license = hash["license"]
          license.should have_key("memory_limit")
          expect(license["memory_limit"]).to eq(42)
        end
      end

    end

  end

  describe VCAP::CloudController::StackatoLicenseController, type: :controller do
    let(:current_user) { make_user_with_default_space(:admin => true) }

    attr_accessor :headers

    before(:each, admin: true) do
      self.headers = headers_for(current_user, admin_scope: true)
    end
    before(:each, admin: false) do
      self.headers = headers_for(current_user, admin_scope: false)
    end

    before(:each) do
      Kato::Config.set('cluster', 'no_license_required', 42)
      Kato::Config.set('cluster', 'license', 'type: microcloud', force: true)
      Kato::Config.set('cluster', 'license_checking', true)
      header 'AUTHORIZATION', headers['HTTP_AUTHORIZATION']
    end

    def encode_license(license)
      Yajl::Encoder.encode({ license: hashed_license_from_hash(license) })
    end

    it 'should parse a given license', admin: true do
      new_license = {
        organization: 'example.com',
        serial: 'ABCD1234',
        type: 'paid',
        memory_limit: 25,
        expiration: '9999-01-01',
      }
      post '/v2/stackato/license/parse', encode_license(new_license), headers
      expect(last_response.status).to eq(200)
      result = Yajl::Parser.parse(last_response.body)

      expect(result.symbolize_keys).to eq(new_license)
    end

    it 'should accept a valid license', admin: true do
      new_license = {
        organization: 'example.com',
        serial: 'ABCD1234',
        type: 'paid',
        memory_limit: 25,
        expiration: '9999-01-01',
      }
      put '/v2/stackato/license', encode_license(new_license), headers
      expect(last_response.status).to eq(200)
      expect(Kato::Config.get('cluster', 'license').symbolize_keys).to eq(new_license)
    end

    it 'should reject an invalid license', admin: true do
      put '/v2/stackato/license', Yajl::Encoder.encode({license: 'BAD LICENSE'}), headers
      expect(last_response.status).not_to eq(200)
    end

    it 'should not allow non-admin to set a license', admin: false do
      new_license = {
        organization: 'example.com',
        serial: 'ABCD1234',
        type: 'paid',
        memory_limit: 25,
        expiration: '9999-01-01',
      }
      put '/v2/stackato/license', encode_license(new_license), headers
      expect(last_response.status).to eq(403)
    end

  end
end
