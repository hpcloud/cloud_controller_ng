require 'cloud_controller/dea/nats_messages/dea_advertisment'
require 'cloud_controller/dea/eligible_advertisement_filter'

module VCAP::CloudController
  module Dea
    class Pool
      def initialize(config, message_bus)
        @advertise_timeout = config[:dea_advertisement_timeout_in_seconds]
        @message_bus = message_bus
        @dea_advertisements = []
      end

      def register_subscriptions
        message_bus.subscribe('dea.advertise') do |msg|
          process_advertise_message(msg)
        end

        message_bus.subscribe('dea.shutdown') do |msg|
          process_shutdown_message(msg)
        end
      end

      def process_advertise_message(message)
        advertisement = NatsMessages::DeaAdvertisement.new(message, Time.now.utc.to_i + @advertise_timeout)

        mutex.synchronize do
          remove_advertisement_for_id(advertisement.dea_id)
          @dea_advertisements << advertisement
        end
      end

      def process_shutdown_message(message)
        fake_advertisement = NatsMessages::DeaAdvertisement.new(message, Time.now.utc.to_i + @advertise_timeout)

        mutex.synchronize do
          remove_advertisement_for_id(fake_advertisement.dea_id)
        end
      end

      def find_dea(criteria)
        mutex.synchronize do
          prune_stale_deas

          best_dea_ad = EligibleAdvertisementFilter.new(@dea_advertisements, criteria[:app_id]).
              only_with_disk(criteria[:disk] || 0).
              only_meets_needs(criteria[:mem], criteria[:stack]).
              only_from_zone(criteria[:zone]).
              az_with_fewest_instances_of_app.
              only_in_zone_with_fewest_instances.
              only_fewest_instances_of_app.
              upper_half_by_memory.
              sample

          best_dea_ad && best_dea_ad.dea_id
        end
      end

      def get_dea_zones
        zones = {
          'default' => []
        }
        @dea_advertisements.each do |ad|
          if (ad.zone && (ad.zones == ["default"])) # ad.zone was passed but ad.zones was not configured
            if zones[ad.zone].nil?
              zones[ad.zone] = []
            end

            zones[ad.zone].push ad.dea_ip
          end

          if ad.zones
            ad.zones.each do |zone|
              if zones[zone].nil?
                zones[zone] = []
              end

              next if zones[zone].include? ad.dea_ip
              zones[zone].push ad.dea_ip
            end
          end
        end

        zones
      end

      def get_dea_availability_zones
        zones = {
            'default' => []
        }
  
        @dea_advertisements.each do |ad|
          if ad.availability_zone
            if zones[ad.availability_zone].nil?
              zones[ad.availability_zone] = []
            end

            zones[ad.availability_zone].push ad.dea_ip
          end
        end

        zones
      end

      def mark_app_started(opts)
        dea_id = opts[:dea_id]
        app_id = opts[:app_id]

        @dea_advertisements.find { |ad| ad.dea_id == dea_id }.increment_instance_count(app_id)
      end

      def get_active_deas
        prune_stale_deas
        @dea_advertisements.dup
      end

      def reserve_app_memory(dea_id, app_memory)
        @dea_advertisements.find { |ad| ad.dea_id == dea_id }.decrement_memory(app_memory)
      end

      private

      attr_reader :message_bus

      def prune_stale_deas
        now = Time.now.utc.to_i
        @dea_advertisements.delete_if { |ad| ad.expired?(now) }
      end

      def remove_advertisement_for_id(id)
        @dea_advertisements.delete_if { |ad| ad.dea_id == id }
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end
