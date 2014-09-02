require "cloud_controller/dea/nats_messages/advertisment"

module VCAP::CloudController
  module Dea
    module NatsMessages
      class DeaAdvertisement < Advertisement
        def dea_id
          stats["id"]
        end

        def dea_ip
          stats["ip"]
        end

        def increment_instance_count(app_id)
          stats["app_id_to_count"][app_id] = num_instances_of(app_id) + 1
        end

        def num_instances_of(app_id)
          stats["app_id_to_count"].fetch(app_id, 0)
        end

        def availability_zone
          stats.fetch("placement_properties", {}).fetch("availability_zone", "default")
        end

        def physical_memory
          stats["physical_memory"]
        end

        def zone
          stats.fetch("placement_properties", {}).fetch("zone", "default")
        end
      end
    end
  end
end
