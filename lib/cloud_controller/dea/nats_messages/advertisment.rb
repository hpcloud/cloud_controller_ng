module VCAP::CloudController
  module Dea
    module NatsMessages
      class Advertisement
        attr_reader :stats

        def initialize(stats, expires)
          @stats = stats
          @expiration = expires
        end

        def available_memory
          stats['available_memory']
        end

        def decrement_memory(mem)
          stats['available_memory'] -= mem
        end

        def available_disk
          stats['available_disk']
        end

        def expired?(now)
          now.to_i >= @expiration
        end

        def meets_needs?(mem, stack)
          has_sufficient_memory?(mem) && has_stack?(stack)
        end

        def has_stack?(stack)
          stats['stacks'].include?(stack)
        end

        def has_sufficient_memory?(mem)
          available_memory >= mem
        end

        def has_sufficient_disk?(disk)
          return true unless available_disk
          available_disk >= disk
        end

        def zones
          stats.fetch("placement_properties", {}).fetch("zones", ["default"])
        end

        def zone
          stats.fetch("placement_properties", {}).fetch("zone", "default")
        end
  
        def accepts_zone?(req_zone)
          # if the ad.zones were manually configured, ignore the ad.zone
          ad_zones = self.zones || ['default']
          ad_zone = (ad_zones != ["default"]) ? nil : self.zone
          (ad_zone == req_zone) || (ad_zones.include? req_zone)
        end
      end
    end
  end
end
