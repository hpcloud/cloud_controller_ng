
require "kato/cluster/status"

module VCAP::CloudController
  class StackatoStatusController < RestController::BaseController

    def get_status
      Yajl::Encoder.encode(Kato::Cluster::Status.get_status)
    end

    get "/v2/stackato/status", :get_status

  end
end
