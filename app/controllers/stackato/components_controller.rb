
require "kato/cluster/manager"
require "kato/cluster/node"
require "kato/exceptions"
require "kato/node_process_controller"

module VCAP::CloudController
  class StackatoComponentsController < RestController::Base

    # Return `kato process list` as JSON
    def get_components
      raise Errors::NotAuthorized unless roles.admin?

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

    def put_component(node_id, component_name)
      raise Errors::NotAuthorized unless roles.admin?
      check_maintenance_mode
      action = params["action"]

      if not ["start", "stop", "restart"].include? action
        raise Errors::StackatoComponentUpdateInvalid.new("action", action)
      elsif not node_id or not (Kato::Config.get("node") || {}).has_key? node_id
        raise Errors::StackatoComponentUpdateInvalid.new("node", node_id)
      elsif not component_name =~ /^\w+$/
        raise Errors::StackatoComponentUpdateInvalid.new("component", component_name)
      end

      logger.info("#{action} #{component_name} (#{node_id})")

      if component_name == "cloud_controller"
        # Supervisord does not have a "restart" command.
        # Therefore, there is no way to fire off a "restart me"
        # command and rely on an external process to restart us.
        # Instead we can simply kill this CC and node_process_controller will
        # auto-restart us.
        exit!
      else
        node_process_controller = Kato::NodeProcessController.new(node_id)
        begin
          if action == "start"
            node_process_controller.start_process(component_name)
          elsif action == "stop"
            node_process_controller.stop_process(component_name)
          elsif action == "restart"
            node_process_controller.restart_process(component_name)
          end
        rescue Exception => e
          if e.message == "BAD_NAME: " + component_name
            raise Errors::StackatoComponentUpdateInvalid.new("component", component_name)
          else
            raise
          end
        end
      end
      [204, {}, nil]
    end

    def underscore_process_name(process_name)
      process_name.gsub(/\-/, '_')
    end

    get "/v2/stackato/components", :get_components
    put "/v2/stackato/components/:node_id/:component_name", :put_component

  end
end
