
require "kato/cluster/status"

module VCAP::CloudController
  class StackatoStatusController < RestController::Base
    allow_unauthenticated_access

    def get_status
      Yajl::Encoder.encode(Kato::Cluster::Status.get_status)
    end

    get "/stackato/status", :get_status

  end
end
