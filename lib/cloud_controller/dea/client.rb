require 'cloud_controller/dea/app_stopper'
require 'cloud_controller/dea/file_uri_result'
require 'stackato/logyard'

module VCAP::CloudController
  module Dea
    module Client
      ACTIVE_APP_STATES = [:RUNNING, :STARTING].freeze
      class << self
        include VCAP::Errors

        attr_reader :config, :message_bus, :dea_pool, :stager_pool, :message_bus

        def configure(config, message_bus, dea_pool, stager_pool, blobstore_url_generator, docker_registry)
          @config = config
          @message_bus = message_bus
          @dea_pool = dea_pool
          @stager_pool = stager_pool
          @blobstore_url_generator = blobstore_url_generator
          @docker_registry = docker_registry
        end

        def start(app, options={})
          instances_to_start = options[:instances_to_start] || app.instances
          start_instances_in_range(app, ((app.instances - instances_to_start)...app.instances))
          app.routes_changed = false
        end

        def run
          @dea_pool.register_subscriptions
        end

        def active_deas
          @dea_pool.get_active_deas
        end

        def stop(app)
          app_stopper.publish_stop(:droplet => app.guid)
        end

        def dea_zones
          @dea_pool.get_dea_zones
        end

        def dea_availability_zones
          @dea_pool.get_dea_availability_zones
        end

        def find_specific_instance(app, options={})
          message = { droplet: app.guid }
          message.merge!(options)

          dea_request_find_droplet(message, timeout: 2).first
        end

        def find_instances(app, message_options={}, request_options={})
          message = { droplet: app.guid }
          message.merge!(message_options)

          request_options[:result_count] ||= app.instances
          request_options[:timeout] ||= 2

          dea_request_find_droplet(message, request_options)
        end

        def find_all_instances(app)
          num_instances = app.instances
          all_instances = {}

          flapping_indices = health_manager_client.find_flapping_indices(app)

          flapping_indices.each do |entry|
            index = entry['index']
            if index >= 0 && index < num_instances
              all_instances[index] = {
                  state: 'FLAPPING',
                  since: entry['since'],
				  docker_id: entry['docker_id'],
              }
            end
          end

          message = {
              states: [:STARTING, :RUNNING],
              version: app.version,
          }

          expected_running_instances = num_instances - all_instances.length
          if expected_running_instances > 0
            request_options = { expected: expected_running_instances }
            running_instances = find_instances(app, message, request_options)

            running_instances.each do |instance|
              index = instance['index']
              if index >= 0 && index < num_instances
                all_instances[index] = {
                    state: instance['state'],
                    since: instance['state_timestamp'],
                    debug_ip: instance['debug_ip'],
                    debug_port: instance['debug_port'],
                    console_ip: instance['console_ip'],
                    console_port: instance['console_port'],
					# For stackato-ssh
                    host_ip: instance['host_ip'],
                    app_ip: instance['app_ip'],
                    # Docker-specific information
                    docker_id: instance['docker_id'],
                }
              end
            end
          end

          num_instances.times do |index|
            unless all_instances[index]
              all_instances[index] = {
                  state: 'DOWN',
                  since: Time.now.utc.to_i,
              }
            end
          end

          all_instances
        end

        def change_running_instances(app, delta)
          if delta > 0
            range = (app.instances - delta...app.instances)
            start_instances_in_range(app, range)
          elsif delta < 0
            range = (app.instances...app.instances - delta)
            stop_indices(app, range.to_a)
          end
        end

        # @param [Enumerable, #each] indices an Enumerable of indices / indexes
        def start_instances(app, indices)
          insufficient_resources_error = false
          indices.each do |idx|
            begin
              start_instance_at_index(app, idx)
            rescue Errors::ApiError => e
              if e.name == 'InsufficientRunningResourcesAvailable'
                insufficient_resources_error = true
              else
                raise e
              end
            end
          end

          raise Errors::ApiError.new_from_details('InsufficientRunningResourcesAvailable') if insufficient_resources_error
        end

        def start_instance_at_index(app, index)
          start_message = Dea::StartAppMessage.new(app, index, config, @blobstore_url_generator, @docker_registry)

          unless start_message.has_app_package? || start_message.has_docker_image?
            logger.error "dea-client.no-package-found", guid: app.guid
            raise Errors::ApiError.new_from_details("AppPackageNotFound", app.guid)
          end

          dea_id = dea_pool.find_dea(mem: app.memory, disk: app.disk_quota, stack: app.stack.name, app_id: app.guid, zone: app.distribution_zone)
          if dea_id
            dea_publish_start(dea_id, start_message)
            dea_pool.mark_app_started(dea_id: dea_id, app_id: app.guid)
            dea_pool.reserve_app_memory(dea_id, app.memory)
            stager_pool.reserve_app_memory(dea_id, app.memory)
          else
            logger.error 'dea-client.no-resources-available', message: scrub_sensitive_fields(start_message)
            app_info = {
              :name => app.name,
              :guid => app.guid,
              :space_guid => app.space_guid,
            }
            msg = "No DEA available satisfying mem #{app.memory}M, stack #{app.stack.name}, and zone #{app.distribution_zone}"
            instance_identifier = Stackato::Logyard.make_instance_identifier(nil, app_info, -1)
            Stackato::Logyard.report_event('NORESOURCES', msg, instance_identifier)
            raise Errors::ApiError.new_from_details('InsufficientRunningResourcesAvailable')
          end
        end

        # @param [Array] indices an Enumerable of integer indices
        def stop_indices(app, indices)
          app_stopper.publish_stop(
              droplet: app.guid,
              version: app.version,
              indices: indices
          )
        end

        # @param [Array] indices an Enumerable of guid instance ids
        def stop_instances(app_guid, instances)
          app_stopper.publish_stop(
              droplet: app_guid,
              instances: Array(instances)
          )
        end

        def app_stopper
          AppStopper.new(message_bus)
        end

        def get_file_uri_for_active_instance_by_index(app, path, index)
          if index < 0 || index >= app.instances
            msg = "Request failed for app: #{app.name}, instance: #{index}"
            msg << " and path: #{path || '/'} as the instance is out of range."

            raise ApiError.new_from_details('FileError', msg)
          end

          search_criteria = {
              indices: [index],
              version: app.version,
              states: ACTIVE_APP_STATES
          }

          result = get_file_uri(app, path, search_criteria)
          unless result
            msg = "Request failed for app: #{app.name}, instance: #{index}"
            msg << " and path: #{path || '/'} as the instance is not found."

            raise ApiError.new_from_details('FileError', msg)
          end
          result
        end

        def get_file_uri_by_instance_guid(app, path, instance_id)
          result = get_file_uri(app, path, instance_ids: [instance_id])
          unless result
            msg = "Request failed for app: #{app.name}, instance_id: #{instance_id}"
            msg << " and path: #{path || '/'} as the instance_id is not found."

            raise ApiError.new_from_details('FileError', msg)
          end
          result
        end

        def update_uris(app)
          return unless app.staged?
          message = dea_update_message(app)
          dea_publish_update(message)
          app.routes_changed = false
        end

        def find_stats(app)
          search_options = {
              include_stats: true,
              states: [:RUNNING],
              version: app.version,
          }

          running_instances = find_instances(app, search_options)

          stats = {} # map of instance index to stats.
          running_instances.each do |instance|
            index = instance['index']
            if index >= 0 && index < app.instances
              stats[index] = {
                  state: instance['state'],
                  stats: instance['stats'],
              }
            end
          end

          # we may not have received responses from all instances.
          app.instances.times do |index|
            unless stats[index]
              stats[index] = {
                  state: 'DOWN',
                  since: Time.now.utc.to_i,
              }
            end
          end

          stats
        end

        def update_autoscaling_fields(app)
          changes = {appid: app.guid, react: false}
          [:min_cpu_threshold, :max_cpu_threshold, :min_instances, :max_instances,
           :autoscale_enabled].each { |k| changes[k] = app.send(k) }
          health_manager_client.update_autoscaling_fields(changes)
        end
      
      private

        def health_manager_client
          CloudController::DependencyLocator.instance.health_manager_client
        end

        # @param [Enumerable, #each] indices the range / sequence of instances to start
        def start_instances_in_range(app, indices)
          start_instances(app, indices)
        end

        # @return [FileUriResult]
        def get_file_uri(app, path, options)
          if app.stopped?
            msg = "Request failed for app: #{app.name} path: #{path || '/'} "
            msg << 'as the app is in stopped state.'

            raise ApiError.new_from_details('FileError', msg)
          end

          search_options = {
              states: [:STARTING, :RUNNING, :CRASHED],
              path: path,
          }.merge(options)

          if (instance_found = find_specific_instance(app, search_options))
            result = FileUriResult.new
            if instance_found['file_uri_v2']
              result.file_uri_v2 = instance_found['file_uri_v2']
              result.host_ip = instance_found['host_ip']
            end

            uri_v1 = [instance_found['file_uri'], instance_found['staged'], '/', path].join('')
            result.file_uri_v1 = uri_v1
            result.credentials = instance_found['credentials']

            return result
          end

          nil
        end

        def dea_update_message(app)
          {
              droplet: app.guid,
              uris: app.uris,
              version: app.version,
          }
        end

        def dea_publish_update(args)
          logger.debug "sending 'dea.update' with '#{args}'"
          message_bus.publish('dea.update', args)
        end

        def dea_publish_start(dea_id, args)
          logger.debug "sending 'dea.start' for dea_id: #{dea_id} with '#{args}'"
          message_bus.publish("dea.#{dea_id}.start", args)
        end

        def dea_request_find_droplet(args, opts={})
          logger.debug "sending dea.find.droplet with args: '#{args}' and opts: '#{opts}'"
          message_bus.synchronous_request('dea.find.droplet', args, opts)
        end

        def scrub_sensitive_fields(message)
          scrubbed_message = message.dup
          scrubbed_message.delete(:services)
          scrubbed_message.delete(:executableUri)
          scrubbed_message.delete(:env)
          scrubbed_message
        end

        def logger
          @logger ||= Steno.logger('cc.dea.client')
        end
      end
    end
  end
end
