require "spec_helper"

module VCAP::CloudController
  describe VCAP::CloudController::LegacyInfo, type: :controller do
    describe "restricted checks" do
      let(:current_user) { make_user_with_default_space(:admin => true) }
      let(:headers) { headers_for(current_user) }
      let(:is_micro_cloud) { Kato::Cluster::Manager.is_micro_cloud }
      let(:admins) { Kato::Config.get('cloud_controller_ng', 'admins') }
      let(:node_info) { Kato::Config.get('node') }
      
      before(:each) do
        if node_info.nil?
          s = <<-'_EOD_'
127.0.0.1:
  roles:
    base: START
    mdns: START
    primary: START
    controller: START
    router: START
    dea: START
    postgresql: START
    mysql: START
    filesystem: START
          _EOD_
          Kato::Config.set('node', s, :yaml => true)
        end
      end

      after(:each) do
        if !node_info.nil?
          Kato::Config.set('node', 'admins', node_info)
        end
      end
      describe "with no admins" do
        before do
          Kato::Config.set('cloud_controller_ng', 'admins', [])
        end
        it "should have free microclouds, restricted other" do
          get "/v2/stackato/info", {}, headers
          expect(last_response.status).to be(200)
          hash = Yajl::Parser.parse(last_response.body)
          expect(hash["restricted"]).to be(!is_micro_cloud)
        end
      end
      describe "with 1 admin" do
        before do
          Kato::Config.set('cloud_controller_ng', 'admins', ['fred'])
        end
        it "should be restricted" do
          get "/v2/stackato/info", {}, headers
          expect(last_response.status).to be(200)
          hash = Yajl::Parser.parse(last_response.body)
          expect(hash["restricted"]).to be(false)
        end
      end
      
      describe "with 2 admins" do
        before do
          Kato::Config.set('cloud_controller_ng', 'admins', ['fred'])
        end
        it "should still be restricted" do
          get "/v2/stackato/info", {}, headers
          expect(last_response.status).to be(200)
          hash = Yajl::Parser.parse(last_response.body)
          expect(hash["restricted"]).to be(false)
        end
      end
    end
  end
end