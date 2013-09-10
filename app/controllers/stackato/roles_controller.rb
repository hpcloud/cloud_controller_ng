
require "kato/cluster/manager"
require "kato/cluster/node"
require "kato/exceptions"

module VCAP::CloudController
  class StackatoRolesController < RestController::Base

    # Example output...
    # {
    #     "available": {
    #       # shows available roles and associated processes
    #       "controller" => [
    #         "nginx",
    #         "postgresql",
    #         "nats_server",
    #         "redis_server",
    #         "cloud_controller",
    #         "health_manager"
    #       ],
    #       "stager" => [
    #        "prealloc",
    #        "stager"
    #       ],
    #       "dea" => [
    #        "prealloc",
    #        "dea"
    #       ],
    #     },
    #     "nodes": {
    #         "192.168.0.1": [ "controller", "router" ],
    #         "192.168.0.2": [ "dea", "stager" ]
    #     },
    #     "required" : [
    #       "mdns",
    #       "controller",
    #       "stager",
    #       "router",
    #       "dea"
    #     ]
    # }
    #
    def list
      raise Errors::NotAuthorized unless roles.admin?
      available_node_role_names =
        Kato::Cluster::RoleManager::available_role_names
      nodes = {}
      Kato::Config.get("node").each_pair do |node_id, node|
        nodes[node_id] = node["roles"].keys rescue []
      end
      available_node_role_processes = {}
      available_node_role_names.each do |node_role_name|
        available_node_role_processes[node_role_name] =
          Kato::Cluster::RoleManager.role_process_names(node_role_name) || []
      end
      Yajl::Encoder.encode({
        :available => available_node_role_processes,
        :nodes => nodes,
        :required => Kato::Cluster::RoleManager.required_role_names
      })
    end

    # Example output...
    # [ "controller", "router" ]
    #
    def get_node(node_id)
      raise Errors::NotAuthorized unless roles.admin?
      node = Kato::Config.get("node", node_id)
      unless node
        raise Errors::StackatoNodeDoesNotExists.new(node_id)
      end
      node_roles = node["roles"].keys rescue []
      Yajl::Encoder.encode(node_roles)
    end

    # Example POST body...
    # [ "controller", "router" ]
    #
    def update_node(node_id)
      raise Errors::NotAuthorized unless roles.admin?
      unless Kato::Config.get("node", node_id)
        raise Errors::StackatoNodeDoesNotExists.new(node_id)
      end
      node_roles = Yajl::Parser.parse(body)
      logger.info("Updating roles for node #{node_id} to #{node_roles}")
      begin
        node = Kato::Cluster::Node.new(node_id)
        existing_node_roles = node.get_configured_role_names
        add_node_roles = node_roles - existing_node_roles
        if add_node_roles.size > 0
          node.add_roles(add_node_roles)
        end
        remove_node_roles = existing_node_roles - node_roles
        if remove_node_roles.size > 0
          node.rm_roles(remove_node_roles)
        end
      rescue KatoBadParamsException => e
        raise Errors::StackatoClusterRolesNodeUpdateError.new(e.message)
      end
      [204, {}, nil]
    end

    get "/v2/stackato/cluster/roles", :list
    get "/v2/stackato/cluster/roles/:node_id", :get_node
    put "/v2/stackato/cluster/roles/:node_id", :update_node

  end
end
