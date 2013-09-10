
require "kato/config"
require "kato/cluster/manager"

module VCAP::CloudController
  class StackatoInfoController < RestController::Base
    allow_unauthenticated_access

    # API version of "kato info"
    # {
    #    "nodes": {
    #      "192.168.0.1": {
    #        "roles" : [
    #           "controller",
    #           "router",
    #           ...
    #        ]
    #      }
    #      "192.168.0.2": {
    #        "roles" : [
    #           "dea",
    #           "stager",
    #           ...
    #        ]
    #      }
    #    },
    #    "mbusip" : "127.0.0.1",
    #    "restricted" : "True",
    #    "admins": [
    #      "betty@rubble.com,
    #      "fred@flintstone.com
    #    ],
    #    "micro_cloud" : true,
    #    "endpoint": "api.stackato-nrb6.local"
    # }
    #
    def get_info
      endpoint = Kato::Config.get("cluster", "endpoint")
      mbusip = Kato::Config.get("cluster", "mbusip")
      nodes = {}
      Kato::Config.get("node").each_pair do |node_id, node|
        role_names = node["roles"].keys rescue []
        nodes[node_id] = { "roles" => role_names }
      end
      admins = (Kato::Config.get("cloud_controller", "admins") or [])

      is_micro_cloud = Kato::Cluster::Manager.is_micro_cloud

      # *everything* other than a ucloud with zero admins is restricted
      restricted = (not (is_micro_cloud and not (admins and admins.length)))

      Yajl::Encoder.encode({
        :endpoint => endpoint,
        :mbusip => mbusip,
        :micro_cloud => is_micro_cloud,
        :restricted => restricted,
        :nodes => nodes,
        :admins => admins,
        :UUID => ::STACKATO_UUID
      })
    end

    get "/v2/stackato/info", :get_info

  end
end
