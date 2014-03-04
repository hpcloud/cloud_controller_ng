module VCAP::CloudController
  class StatsController < RestController::ModelController
    path_base "apps"
    model_class_name :App

    get  "#{path_guid}/stats", :stats
    def stats(guid, opts = {})
      app = find_guid_and_validate_access(:read, guid)
      stats = DeaClient.find_stats(app, opts)

      stats.each do |instance_index, data|
        data[:stats]["usage"]["mem"] =  data[:stats]["usage"]["mem"].to_i
        data[:stats]["usage"]["disk"] =  data[:stats]["usage"]["disk"].to_i
      end

      [HTTP::OK, Yajl::Encoder.encode(stats)]
    end
  end
end
