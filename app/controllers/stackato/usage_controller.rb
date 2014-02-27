
require "yajl"
require "cloud_controller/stackato/droplet_accountability"

module VCAP::CloudController
  class StackatoStatusController < RestController::Base

    def map_zone_usage(deas, zones)
      zones_breakdown = []
      zones.each do | zone_name, deas_in_zone |
        zone = {:name => zone_name, :dea_ids => [], :total_allocated => 0, :total_used => 0, :total_available => 0}
        deas_in_zone.each do |dea_ip|
          dea_index = deas.find_index { |dea| dea[:dea_ip] == dea_ip }
          if !dea_index.nil?
            dea = deas[dea_index]
            zone[:dea_ids] << dea[:dea_id]
            zone[:total_allocated] += dea[:total_allocated]
            zone[:total_used] += dea[:total_used]
            zone[:total_available] += dea[:total_available]
          end
        end
        zones_breakdown << zone
      end
      zones_breakdown
    end

    def map_cluster_usage(deas)
      cluster = {:total_allocated => 0, :total_used => 0, :total_available => 0, :total_assigned => 0}
      deas.each do |dea|
        cluster[:total_allocated] += dea[:total_allocated]
        cluster[:total_used] += dea[:total_used]
        cluster[:total_available] += dea[:total_available]
      end
     cluster[:total_assigned] = Organization.join(:quota_definitions, :id => :quota_definition_id).sum(:memory_limit)
     cluster
    end

    def usage
      raise Errors::NotAuthorized unless roles.admin?

      deas = StackatoDropletAccountability.get_all_dea_stats
      stats = {
        :placement_zones => map_zone_usage(deas, DeaClient.dea_zones), # memory usage broken down by placement zones
        :availability_zones => map_zone_usage(deas, DeaClient.dea_availability_zones), # memory usage broken down by availability zones
        :cluster => map_cluster_usage(deas), # memory usage summarized across the cluster
        :deas => deas # memory usage broken down by dea
      }

      Yajl::Encoder.encode(stats)
    end

    get "/v2/usage", :usage
  end
end