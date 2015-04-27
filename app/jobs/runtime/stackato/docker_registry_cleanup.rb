require 'json'
require 'net/http'
require 'set'
require "cloud_controller/dependency_locator"

module VCAP::CloudController
  module Jobs
    module Runtime
      module Stackato
        class DockerRegistryCleanup < Struct.new(:config)

          def perform
            logger = Steno.logger("cc.stackato.clock")
            logger.info "Performing docker registry cleanup job"
            target_size_in_megabytes = config[:docker_apps][:storage_limit_mb] || 10240
            droplet_hashes = Set.new
            VCAP::CloudController::App.where{docker_image != nil}.each do |app|
              droplet_hashes.merge app.droplets.map(&:droplet_hash)
            end
            docker_registry = CloudController::DependencyLocator.instance.docker_registry
            url = URI("http://#{docker_registry}/v1/cleanup/")
            req = Net::HTTP::Post.new(url.request_uri)
            req.content_type = "application/json"
            req.body = {
              :cleanup_limit => target_size_in_megabytes,
              :known_hashes => droplet_hashes.to_a}.to_json
            http = Net::HTTP.new(url.hostname, url.port)
            logger.info("Cleaning up docker registry; aiming for #{target_size_in_megabytes} MB (#{droplet_hashes.length} in use)")
            response = http.request(req)
            begin
              response.value
            rescue
              logger.error("Failed to clean up docker registry: #{response.code}: #{response.message}\n#{response.body}")
            else
              logger.info("Cleaned up docker registry: #{response.code}: #{response.message}")
            end
          end

          def job_name_in_configuration
            :docker_registry_cleanup
          end

          def max_attempts
            1
          end
        end
      end
    end
  end
end
