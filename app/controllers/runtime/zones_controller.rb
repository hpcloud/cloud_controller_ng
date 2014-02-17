
module VCAP::CloudController
  class ZonesController < RestController::ModelController

    def zone(zone_name)
      zones = DeaClient.dea_zones

      formatted_zones = format_zones(zones, '/v2/zones/', zone_name)

      if formatted_zones[:resources].size == 1
        [HTTP::OK, Yajl::Encoder.encode(formatted_zones[:resources][0])]
      else
        raise Errors::StackatoZoneDoesNotExist.new(zone_name)
      end
    end

    def availability_zone(zone_name)
      zones = DeaClient.dea_availability_zones

      formatted_zones = format_zones(zones, '/v2/availability_zones/', zone_name)

      if formatted_zones[:resources].size == 1
        [HTTP::OK, Yajl::Encoder.encode(formatted_zones[:resources][0])]
      else
        raise Errors::StackatoZoneDoesNotExist.new(zone_name)
      end
    end

    def list_zones
      zones = DeaClient.dea_zones

      formatted_zones = format_zones(zones, '/v2/zones/')

      [HTTP::OK, Yajl::Encoder.encode(formatted_zones)]
    end

    def list_availability_zone
      zones = DeaClient.dea_availability_zones

      formatted_zones = format_zones(zones, '/v2/availability_zones/')

      [HTTP::OK, Yajl::Encoder.encode(formatted_zones)]
    end

    def format_zones(zones, zone_uri, search_filter = nil)
      if search_filter.nil?
        search_filter = params['q']
      end
      if search_filter && search_filter.include?(':')
        search_filter = search_filter.split(':')[1]
      end

      ret_data = {
          :next_url => nil,
          :prev_url => nil,
          :resources => [],
          :total_pages => 1
      }

      zones.each_pair do |zone_name, zone_deas|
        # Cull empty zones
        if zone_deas.size == 0
          next
        end

        if search_filter.nil?
          ret_data[:resources].push(format_zone(zone_name, zone_deas, zone_uri))
        elsif search_filter.include?('*') && zone_name.start_with?(search_filter.chomp('*'))
            ret_data[:resources].push(format_zone(zone_name, zone_deas, zone_uri))
        elsif zone_name == search_filter
            ret_data[:resources].push(format_zone(zone_name, zone_deas, zone_uri))
        end
      end

      ret_data[:total_results] = ret_data[:resources].size

      ret_data
    end

    def format_zone(zone_name, zone_deas, zone_uri)
      ret_data = {
          :entity => {
              :guid => zone_name,
              :name => zone_name,
              :deas => []
          },
          :metadata => {
              :created_at => nil,
              :guid => zone_name,
              :updated_at => nil,
              :url => zone_uri + zone_name
          }
      }

      zone_deas.each do |dea|
        ret_data[:entity][:deas].push dea
      end

      ret_data
    end

    get '/v2/zones', :list_zones
    get '/v2/zones/:zone_name', :zone

    get '/v2/availability_zones', :list_availability_zone
    get '/v2/availability_zones/:zone_name', :availability_zone

  end
end