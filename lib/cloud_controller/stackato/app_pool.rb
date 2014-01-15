
require "steno"

module VCAP::CloudController
  class StackatoAppPool
    class << self
      def dea_droplet_map
        @dea_droplet_map ||= {}
      end

      def logger
        @logger ||= Steno.logger("cc.stackato.app_pool")
      end

      def add_dea_heartbeat(dea_heartbeat)
        mutex.synchronize do
          dea_id = dea_heartbeat['dea']

          # If we don't have any droplet info for the dea, init new.
          if dea_droplet_map[dea_id].nil?
            dea_droplet_map[dea_id] = {'droplets'=>{}}
          end

          dea_droplets = dea_droplet_map[dea_id]['droplets']

          heartbeat_droplet_instances = []

          # Add the droplet data to the dea
          dea_heartbeat['droplets'].each do |droplet|
            droplet_id = droplet['droplet']
            droplet_instance = droplet['instance']
            heartbeat_droplet_instances.push(droplet_instance)

            if dea_droplets[droplet_id].nil?
              dea_droplets[droplet_id] = {'instances'=>{}}
            end

            dea_droplets[droplet_id]['instances'][droplet_instance] = droplet
          end

          # Remove the droplets that no longer exist in the heartbeat from dea_map
          dea_droplets.each_pair do |droplet_id, droplet_data|
            droplet_data['instances'].each_pair do |instance_id, instance_data|
                unless heartbeat_droplet_instances.include? instance_id
                  droplet_data['instances'].delete(instance_id)
                end
            end
            if droplet_data['instances'].size == 0
              dea_droplets.delete(droplet_id)
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