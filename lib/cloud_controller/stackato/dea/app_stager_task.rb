require 'cloud_controller/dea/app_stager_task'

module VCAP::CloudController
  module Dea
    class StackatoAppStagerTask < AppStagerTask

      def stage(&completion_callback)
        find_stager_retry
        if !@stager_id
          parts = ["stack #{@app.stack.name}", "mem #{@app.memory}"]
          if @app.distribution_zone && @app.distribution_zone != "default"
            partString = parts.join(", ") + ", and zone #{@app.distribution_zone}"
          else
            partString = parts.join(" and ")
          end
          available_zones = available_placement_zones
          if available_zones.size > 1 || available_zones.first != "default"
              partString += ". Requested placement_zone: #{@app.distribution_zone}, available placement zones: #{available_zones.join(" ")}"
          end
          raise Errors::ApiError.new_from_details('StagingError', "no available stagers for #{partString}; available mem: #{staging_task_memory_mb}, disk: #{staging_task_disk_mb}")
        end
        finish_stage(&completion_callback)
      end
    
      def available_placement_zones
        available_zones = []
        Kato::Cluster::Manager.node_ids_for_process("dea_ng").each do |node_id|
          zones = Kato::Config.get("dea_ng", "placement_properties/zones",
                                   :node => node_id)
          if zones
            # If this array has zero items then add nothing.
            available_zones += zones
          else
            zone = Kato::Config.get("dea_ng", "placement_properties/zone",
                                    :node => node_id)
            available_zones << ("default" || zone)
          end
        end
        available_zones.uniq.sort
      end
      
      private
      
      def find_stager_retry
        # Bug 104558 - Allow for dead droplet-slots to be made available
        # Same code as in StackatoStagers.stage_if_needed
        num_tries = @config[:staging].fetch(:num_repeated_tries, 10)
        delay = @config[:staging].fetch(:time_between_tries, 3)
        num_tries.times do | iter |
          if iter > 0
            logger.warn("#{iter}/#{num_tries}: Waiting #{delay} secs for next attempt to find a stager for #{@app.name}")
            sleep delay
          end
          @stager_id = @stager_pool.find_stager(@app.stack.name, staging_task_memory_mb, staging_task_disk_mb, @app.distribution_zone)
          if @stager_id
            return @stager_id
          end
        end
        nil
      end

    end
  end
end
