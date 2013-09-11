
require "kato/logyard"

module VCAP::CloudController
  class StackatoDrainsController < RestController::Base

    def list
      raise Errors::NotAuthorized unless roles.admin?
      drain_uris = Kato::Logyard.run_logyard_remote "list", []
      drain_statuses = Kato::Logyard.run_logyard_remote "status", []
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
      drain_list = []
      drain_hash.each do |drain_name, drain|
        drain[:name] = drain_name
        drain_list << drain
      end
      Yajl::Encoder.encode(drain_list)
    end

    def add
      raise Errors::NotAuthorized unless roles.admin?
      drain = Yajl::Parser.parse(body)
      unless drain["name"]
        raise Errors::StackatoDrainAddNameRequired.new
      end
      unless drain["uri"]
        raise Errors::StackatoDrainAddUriRequired.new
      end
      logger.info("Adding drain with args: #{drain}")
      Kato::Logyard.add_drain drain["name"], drain["uri"]
      [204, {}, nil]
    end

    def delete(name)
      raise Errors::NotAuthorized unless roles.admin?
      logger.info("Deleting drain '#{name}'")
      response = Kato::Logyard.run_logyard_remote "delete", [name]
      Yajl::Encoder.encode(response)
    end

    # TODO:Stackato: We need to limit scope and define what this API is.
    #                "Anything that logyard-cli accepts" is too broad.

    # Exposing logyard-cli/logyard-remote via CC API
    get    "/v2/stackato/drains",       :list
    post   "/v2/stackato/drains",       :add
    delete "/v2/stackato/drains/:name", :delete

  end
end
