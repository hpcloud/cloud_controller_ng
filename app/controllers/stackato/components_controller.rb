
require "kato/cluster/manager"
require "kato/cluster/node"
require "kato/exceptions"

module VCAP::CloudController
  class StackatoComponentsController < RestController::Base
    allow_unauthenticated_access

    def get_components
      # Return `kato process list` as JSON
      node_ids = Kato::Cluster::Manager.node_ids
      nodes = {}
      node_ids.each do |node_id|
        nodes[node_id] = {}
        begin
          node = Kato::Cluster::Node.new(node_id)
          # configured processes
          node.get_assigned_processes.each do |process|
            if not process.is_running?
              state = :STOPPED
            elsif not process.is_ready?
              state = :STARTING
            else
              state = :RUNNING
            end
            nodes[node_id][underscore_process_name(process.name)] = state
          end
          # rogue processes
          node.get_rogue_process_names.each do |process_name|
            nodes[node_id][underscore_process_name(process_name)] = :ROGUE
          end
        rescue KatoSupervisordNotRunningException => e
          raise Errors::StackatoSupervisordNotRunning.new(node_id, e.message)
        end
      end
      Yajl::Encoder.encode(nodes)
    end

    def underscore_process_name(process_name)
      process_name.gsub(/\-/, '_')
    end

    get "/stackato/components", :get_components

  end
end
