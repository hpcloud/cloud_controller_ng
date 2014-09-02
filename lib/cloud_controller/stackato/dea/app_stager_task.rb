require 'cloud_controller/dea/app_stager_task'

module VCAP::CloudController
  module Dea
    class StackatoAppStagerTask < AppStagerTask
    
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
    end
  end
end
