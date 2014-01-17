
module VCAP::CloudController
  class ZonesController < RestController::ModelController

    def list_zones
      zones = DeaClient.dea_zones
      [HTTP::OK, Yajl::Encoder.encode({"zones" => zones})]
    end

    get "/v2/zones", :list_zones

  end
end