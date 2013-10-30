
require "yajl"
require "cloud_controller/stackato/droplet_accountability"

module VCAP::CloudController
  rest_controller :StackatoAppUsage do
    disable_default_routes
    path_base "apps"
    model_class_name :App

    def usage(app_guid)
      app = find_guid_and_validate_access(:read, app_guid)
      
      stats_total = {
        :mem => 0
      }
      allocated_total = {
        :mem => 0
      }

      allocated_total[:mem] = app.total_existing_memory * 1024
      instances = StackatoDropletAccountability.get_app_stats(app)
      instances.each do |index, instance|
        next unless instance["stats"] && instance["stats"]["usage"] && instance["stats"]["usage"]["mem"]
        stats_total["mem"] += instance["stats"]["usage"]["mem"].to_f
      end

      Yajl::Encoder.encode({
        :usage => stats_total,
        :allocated => allocated_total
      })
    end

    get "#{path_guid}/usage", :usage

  end
end
