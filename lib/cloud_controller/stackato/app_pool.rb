
require "steno"

module VCAP::CloudController
  class StackatoAppPool
    class << self
      def droplet_map
        @droplet_map ||= {}
      end

      def logger
        @logger ||= Steno.logger("cc.stackato.app_pool")
      end

      def add_dea_heartbeat(dea_heartbeat)
        mutex.synchronize do
          dea_id = dea_heartbeat['dea']

          # If we don't have any droplet info for the dea, init new.
          if droplet_map[dea_id].nil?
            droplet_map[dea_id] = {}
          end

          dea_droplets = droplet_map[dea_id]

          heartbeat_droplets = []

          # Add the droplet data to the dea
          dea_heartbeat['droplets'].each do |droplet|
            droplet_instance = droplet['instance']
            heartbeat_droplets.push(droplet_instance)

            if dea_droplets[droplet_instance].nil?
              dea_droplets[droplet_instance] = droplet
            end
          end

          # Remove the droplets that no longer exist in the heartbeat from dea_map
          dea_droplets.each_pair do |id, droplet|
            unless heartbeat_droplets.include? id
              dea_droplets.delete(id)
            end
          end
        end
      end

      private

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end