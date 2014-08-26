
require "kato/logyard"

module VCAP::CloudController
  class StackatoDrainsController < RestController::BaseController

    DRAINS_BASE_URL = "/v2/drains"

    def list
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      drain_uris = Kato::Logyard.list_drains
      drain_statuses = Kato::Logyard.status
      drain_hash = {}
      if drain_uris
        drain_uris.each do |drain_name, uri|
          drain_hash[drain_name] ||= {}
          drain_hash[drain_name][:uri] = uri
        end
      end
      if drain_statuses
        drain_statuses.each do |drain_name, status|
          drain_hash[drain_name] ||= {}
          drain_hash[drain_name][:status] = status
        end
      end
      resources = []
      drain_hash.each do |drain_name, drain|
        drain[:name] = drain_name
        resources << {
          :metadata => {
            :guid => drain_name,
            :url => "#{DRAINS_BASE_URL}/#{drain_name}"
          },
          :entity => drain
        }
      end
      Yajl::Encoder.encode({
        :total_results => resources.size,
        :total_pages   => 1,
        :prev_url => nil,
        :next_url => nil,
        :resources => resources
      })
    end

    def get(drain_name)
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      drain_statuses = Kato::Logyard.status({ :drains => [drain_name] })
      unless drain_statuses.size == 1
        raise Errors::ApiError.new_from_details("StackatoDrainNotExists", drain_name)
      end
      drain_uri = Kato::Logyard.drain_uri(drain_name)
      drain_status = drain_statuses.values.first
      Yajl::Encoder.encode({
        :metadata => {
          :guid => drain_name,
          :url => drain_url(drain_name)
        },
        :entity => {
          :name => drain_name,
          :uri => drain_uri,
          :status => drain_status
        }
      })
    end

    def add
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      check_maintenance_mode
      drain = Yajl::Parser.parse(body)
      unless drain["name"]
        raise Errors::ApiError.new_from_details("StackatoDrainAddNameRequired")
      end
      unless drain["uri"]
        raise Errors::ApiError.new_from_details("StackatoDrainAddUriRequired")
      end
      logger.info("Adding drain with args: #{drain}")
      Kato::Logyard.add_drain drain["name"], drain["uri"]

      # Return HTTP 201 (Created) and set the Location header to URL of resource
      [ 201, { "Location" => drain_url(drain["name"]) }, nil ]
    end

    def delete(name)
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      check_maintenance_mode
      logger.info("Deleting drain '#{name}'")
      response = Kato::Logyard.run_logyard_remote "delete", [name]
      Yajl::Encoder.encode(response)
    end

    def drain_url(drain_name)
      [DRAINS_BASE_URL, drain_name].join("/")
    end

    # TODO:Stackato: We need to limit scope and define what this API is.
    #                "Anything that logyard-cli accepts" is too broad.

    # Exposing logyard-cli/logyard-remote via CC API
    get    DRAINS_BASE_URL,            :list
    post   DRAINS_BASE_URL,            :add
    get    "#{DRAINS_BASE_URL}/:name", :get
    delete "#{DRAINS_BASE_URL}/:name", :delete

  end
end
