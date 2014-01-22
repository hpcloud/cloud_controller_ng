module VCAP::CloudController
  module Jobs
    module Runtime
      class EventsCleanup < Struct.new(:cutoff_age_in_days)
        include VCAP::CloudController::TimedJob

        def perform
          Timeout.timeout max_run_time(:events_cleanup) do
            old_events = Event.where("created_at < ?", cutoff_time)
            logger = Steno.logger("cc.background")
            logger.info("Cleaning up #{old_events.count} Event rows")
            old_events.delete
          end
        end

        private

        def cutoff_time
          Time.now - cutoff_age_in_days.days
        end
      end
    end
  end
end
