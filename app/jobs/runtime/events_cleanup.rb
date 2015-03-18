module VCAP::CloudController
  module Jobs
    module Runtime
      class EventsCleanup < Struct.new(:cutoff_age_in_days)
        def perform
          old_events = Event.where("created_at < CURRENT_TIMESTAMP - INTERVAL '? DAY'", cutoff_age_in_days)
          logger = Steno.logger("cc.background")
          logger.info("Cleaning up #{old_events.count} Event rows")
          old_events.delete
        end

        def job_name_in_configuration
          :events_cleanup
        end

        def max_attempts
          1
        end
      end
    end
  end
end
