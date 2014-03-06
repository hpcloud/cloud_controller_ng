module VCAP::CloudController
  class StatsController < RestController::ModelController
    path_base "apps"
    model_class_name :App

    get  "#{path_guid}/stats", :stats
    def stats(guid, opts = {})
      app = find_guid_and_validate_access(:read, guid)
      stats = DeaClient.find_stats(app, opts)

      stats.each_value do |data|
        # When an instance is starting up this value might not yet exist
        dsu = data[:stats]["usage"] rescue nil
        if dsu
          %w/mem disk/.each { |key| dsu[key] = dsu[key].to_i }
        end
      end

      [HTTP::OK, Yajl::Encoder.encode(stats)]
    end
  end
end
