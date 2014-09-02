require "cloud_controller/multi_response_message_bus_request"
require "models/runtime/droplet_uploader"
require "cloud_controller/dea/app_stopper"
require "cloud_controller/backends"

module VCAP::CloudController
  module AppObserver
    class << self
      extend Forwardable

      def configure(backends)
        @backends = backends
      end

      def deleted(app)
        @backends.find_one_to_run(app).stop

        delete_package(app) if app.package_hash
        delete_buildpack_cache(app)
      end
      
      def logger
        @logger ||= Steno.logger("cc.app_observer")
      end

      def updated(app)
        changes = app.previous_changes
        return unless changes

        if changes.has_key?(:state)
          react_to_state_change(app)
        elsif changes.has_key?(:instances)
          # changes[:instances] is reconsulted in Dea::Backend
          react_to_instances_change(app)
        elsif app.version_updated
          @backends.react_to_version_change(app)
        elsif (changes.has_key?(:package_hash) &&
               changes[:package_hash][0] &&
               changes[:package_state] = ["STAGED", "PENDING"])
          @backends.react_to_droplet_hash_change(app)
        elsif (changes.keys & [:min_instances, :max_instances,
                              :min_cpu_threshold, :max_cpu_threshold,
                              :autoscale_enabled]).size > 0 && @health_manager_client
          changes.delete(:updated_at)
          changes[:react] = true
          # Health manager refers to "app.guid" as "app[:appid]"
          changes[:appid] = app.guid
          @backends.update_autoscaling_fields(changes)
        end
      end

      private

      def delete_buildpack_cache(app)
        delete_job = Jobs::Runtime::BlobstoreDelete.new(app.guid, :buildpack_cache_blobstore)
        Jobs::Enqueuer.new(delete_job, queue: "cc-generic").enqueue()
      end

      def delete_package(app)
        delete_job = Jobs::Runtime::BlobstoreDelete.new(app.guid, :package_blobstore)
        Jobs::Enqueuer.new(delete_job, queue: "cc-generic").enqueue()
      end

      def react_to_state_change(app)
        if !app.started?
          @backends.find_one_to_run(app).stop
          return
        end

        staging_backend = @backends.find_one_to_stage(app)
        app.mark_for_restaging if staging_backend.requires_restage?

        if app.needs_staging?
          @backends.validate_app_for_staging(app)
          staging_backend.stage
        else
          @backends.find_one_to_run(app).start
        end
      end

      def react_to_instances_change(app)
        if app.started?
          @backends.find_one_to_run(app).scale
          @backends.broadcast_app_updated(app)
        end
      end
      
    end
  end
end
