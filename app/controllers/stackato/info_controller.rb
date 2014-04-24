
require "kato/config"
require "kato/cluster/manager"
require 'cloud_controller/stackato/cluster_config'
require 'cloud_controller/stackato/vendor_config'

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
      license = Kato::Config.get("cluster", "license")
      endpoint = Kato::Config.get("cluster", "endpoint")
      mbusip = Kato::Config.get("cluster", "mbusip")
      nodes = {}
      (Kato::Config.get("node") || []).each_pair do |node_id, node|
        role_names = node["roles"].keys rescue []
        nodes[node_id] = { "roles" => role_names }
      end
      admins = (Kato::Config.get("cloud_controller", "admins") || [])

      is_micro_cloud = Kato::Cluster::Manager.is_micro_cloud

      # *everything* other than a ucloud with zero admins is restricted
      restricted = !is_micro_cloud || admins.length > 0

      info = {
        :endpoint => endpoint,
        :maintenance_mode => Config.config[:maintenance_mode],
        :mbusip => mbusip,
        :micro_cloud => is_micro_cloud,
        :restricted => restricted,
        :nodes => nodes,
        :admins => admins,
        :vendor_version => StackatoVendorConfig.vendor_version,
        :stackato => {
            :license_accepted => !license.blank?,
            :UUID => STACKATO_UUID
        }
      }
      StackatoClusterConfig.update_license_info(info, license)
      Yajl::Encoder.encode(info)
    end

    get "/v2/stackato/info", :get_info

  end
end
