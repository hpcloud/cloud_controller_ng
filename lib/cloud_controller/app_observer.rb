require 'cloud_controller/multi_response_message_bus_request'
require 'models/runtime/droplet_uploader'
require 'cloud_controller/dea/app_stopper'

module VCAP::CloudController
  module AppObserver
    class << self
      extend Forwardable

      def configure(stagers, runners)
        @stagers = stagers # Instance of StackatoStagers
        @runners = runners # Instance of StackatoRunners
      end

      def deleted(app)
        @runners.runner_for_app(app).stop

        delete_package(app) if app.package_hash
        delete_buildpack_cache(app)
      end
      
      def logger
        @logger ||= Steno.logger('cc.app_observer')
      end

      def updated(app)
        changes = app.previous_changes
        return unless changes

        if changes.key?(:state) || changes.key?(:diego) || changes.key?(:enable_ssh)
          react_to_state_change(app)
        elsif changes.key?(:instances)
          react_to_instances_change(app)
        elsif app.version_updated
          @runners.react_to_version_change(app)
        elsif (changes.has_key?(:package_hash) &&
               changes[:package_hash][0] &&
               changes[:package_state] = ["STAGED", "PENDING"])
          @runners.react_to_droplet_hash_change(app)
        elsif (changes.keys & [:min_instances, :max_instances,
                              :min_cpu_threshold, :max_cpu_threshold,
                              :autoscale_enabled]).size > 0 && @health_manager_client
          changes.delete(:updated_at)
          changes[:react] = true
          # Health manager refers to "app.guid" as "app[:appid]"
          changes[:appid] = app.guid
          @runners.update_autoscaling_fields(changes)
        end
      end

      def routes_changed(app)
        @runners.runner_for_app(app).update_routes if app.started?
      end

      private

      def delete_buildpack_cache(app)
        delete_job = Jobs::Runtime::BlobstoreDelete.new(app.guid, :buildpack_cache_blobstore)
        Jobs::Enqueuer.new(delete_job, queue: 'cc-generic').enqueue
      end

      def delete_package(app)
        delete_job = Jobs::Runtime::BlobstoreDelete.new(app.guid, :package_blobstore)
        Jobs::Enqueuer.new(delete_job, queue: 'cc-generic').enqueue
      end

      def react_to_state_change(app)
        if !app.started?
          @runners.runner_for_app(app).stop
          return
        end

        if app.needs_staging?
          @stagers.validate_app(app)
          @stagers.stager_for_app(app).stage_app
        else
          @runners.runner_for_app(app).start
        end
      end

      def react_to_instances_change(app)
        if app.started?
          @runners.runner_for_app(app).scale
          @runners.broadcast_app_updated(app)
        end
      end
      
    end
  end
end
