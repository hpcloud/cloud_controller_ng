
require "kato/local/node"

module VCAP::CloudController
  class StackatoNodeIdController < RestController::BaseController
    allow_unauthenticated_access

    def get_node_id
      Yajl::Encoder.encode({
        :id   => Kato::Local::Node.get_local_node_id,
        :type => Kato::Local::Node.get_node_type
      })
    end

    get "/v2/stackato/node_id", :get_node_id

  end
end
