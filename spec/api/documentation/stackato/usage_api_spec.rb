require 'active_support/core_ext'
require 'json'
require 'spec_helper'
require 'rspec_api_documentation/dsl'
require "cloud_controller/stackato/droplet_accountability"

resource 'StackatoStatus', type: [:api, :legacy_api] do
  let(:admin_auth_header) { admin_headers['HTTP_AUTHORIZATION'] }

  authenticated_request

  get '/v2/usage' do
    example 'Get total usage statistics' do
      explanation <<-eos
        Get total runtime usage information
      eos

      dea_stats = [
        {
          total_allocated: 5678, # megabytes
          total_used: 1234,      # megabytes
          total_available: 3276, # megabytes
          total_physical: 4096,  # megabytes
        },
        {
          total_allocated: 456,  # megabytes
          total_used: 123,       # megabytes
          total_available: 1638, # megabytes
          total_physical: 2048,  # megabytes
        }
      ]

      allow(VCAP::CloudController::StackatoDropletAccountability)
        .to receive(:get_all_dea_stats)
        .and_return([{dea_id: "dea_id_0", dea_ip: "192.0.2.1"}.merge(dea_stats[0]),
                     {dea_id: "dea_id_1", dea_ip: "192.0.2.2"}.merge(dea_stats[1])])

      allow(VCAP::CloudController::Organization)
        .to receive(:join).with(:quota_definitions, :id => :quota_definition_id)
        .and_return(instance_double(Sequel::Dataset).tap do |dataset|
           expect(dataset).to receive(:sum).with(:memory_limit).and_return(3072)
         end)
      
      allow(VCAP::CloudController::Dea::Client).to receive(:dea_zones)
        .and_return({"one" => ["192.0.2.1"], "two" => ["192.0.2.2"]})

      allow(VCAP::CloudController::Dea::Client).to receive(:dea_availability_zones)
        .and_return({"one" => ["192.0.2.1"], "two" => ["192.0.2.2"]})

      do_request

      # Replace with ActiveSupport version when we upgrade the gem
      deep_symbolize_keys = lambda do |h|
        h.symbolize_keys! if h.respond_to?(:symbolize_keys!)
        if h.respond_to?(:each_value)
          h.each_value { |v| deep_symbolize_keys.call(v) }
        elsif h.respond_to?(:each)
          h.each { |v| deep_symbolize_keys.call(v) }
        end
        h
      end
      response_json = deep_symbolize_keys.call(JSON.parse(response_body))

      expect(response_json[:deas]).
        to eq([
          {dea_id: "dea_id_0", dea_ip: "192.0.2.1"}.merge(dea_stats[0]),
          {dea_id: "dea_id_1", dea_ip: "192.0.2.2"}.merge(dea_stats[1])
          ])

      expect(response_json[:usage][:mem]).
        to eq(dea_stats.map{|s|s[:total_used]}.reduce(:+) * 1024) # KB

      expect(response_json[:allocated][:mem]).
        to eq(dea_stats.map{|s|s[:total_allocated]}.reduce(:+) * 1024) # KB

      expect(response_json[:cluster]).
        to eq(dea_stats[0].merge(dea_stats[1]){|k, v1, v2| v1 + v2}.merge(
                {total_assigned: 3072})) # From quotas above

      expect(response_json[:availability_zones]).to eq([
        {name: "one", dea_ids: ["dea_id_0"]}.merge(dea_stats[0]),
        {name: "two", dea_ids: ["dea_id_1"]}.merge(dea_stats[1])])

      expect(response_json[:placement_zones]).to eq([
        {name: "one", dea_ids: ["dea_id_0"]}.merge(dea_stats[0]),
        {name: "two", dea_ids: ["dea_id_1"]}.merge(dea_stats[1])])

      # Expect no extra keys
      expect(response_json.keys).to match_array [
        :deas, :usage, :allocated, :cluster, :availability_zones, :placement_zones
      ]
    end
  end
end
