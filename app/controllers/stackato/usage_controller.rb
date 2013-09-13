
require "yajl"
require "cloud_controller/stackato/droplet_accountability"

module VCAP::CloudController
  class StackatoStatusController < RestController::Base

    def usage
      raise Errors::NotAuthorized unless roles.admin?

      stats_total = {
        :mem => 0
      }
      allocated_total = {
        :mem => 0
      }

      Models::App.each do |app|
        allocated_total[:mem] += (app.total_existing_memory * 1024)
        instances = StackatoDropletAccountability.get_app_stats(app)
        instances.each do |index, instance|
          next unless instance["stats"] && instance["stats"]["usage"] && instance["stats"]["usage"]["mem"]
          stats_total[:mem] += instance["stats"]["usage"]["mem"].to_f
        end
      end

      Yajl::Encoder.encode({
        :usage => stats_total,
        :allocated => allocated_total
      })

    end

    get "/v2/usage", :usage

  end
end
