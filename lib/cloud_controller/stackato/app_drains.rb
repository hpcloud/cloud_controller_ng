# REST API helper for managing logyard drains specific to an app.
# TODO: move this to kato/lib

require 'uri'
require 'cgi'
require "kato/config"
require "kato/logyard"

module VCAP::CloudController
  class StackatoAppDrains

    DRAIN_NAME_MIN_LENGTH = 4
    DRAIN_NAME_MAX_LENGTH = 25

    # disallow using of ports <10000 to prevent users from potentially
    # connecting to stackato services (redis-server, nats-server ...)
    DRAIN_PORT_MIN = 10000

    def self.logger
      @@logger ||= Steno.logger("cc.stackato.app_drains")
    end

    def self.validate_name(drain_name)
      if drain_name.nil?
        raise Errors::ApiError.new_from_details("StackatoAppDrainInvalidName")
      elsif drain_name.match(/[a-zA-Z\.\-\_]+/).nil?
        raise Errors::ApiError.new_from_details("StackatoAppDrainInvalidName")
      elsif drain_name.length < DRAIN_NAME_MIN_LENGTH
        raise Errors::ApiError.new_from_details("StackatoAppDrainNameMinLength", DRAIN_NAME_MIN_LENGTH)
      elsif drain_name.length > DRAIN_NAME_MAX_LENGTH
        raise Errors::ApiError.new_from_details("StackatoAppDrainNameMaxLength", DRAIN_NAME_MAX_LENGTH)
      end
    end

    def self.validate_uri(uri)
      # min: x://s
      if uri.length < 5
        raise Errors::ApiError.new_from_details("StackatoAppDrainInvalidUri")
      end
    end

    def self.globally_unique_drain_id(app, drain_name)
      # namespaced drain drain_name, calculated from appid.
      "appdrain.#{app.guid}.#{drain_name}"
    end

    # is this drain URI allowed for apps?
    def self.sanitize_uri(uri_string)
      uri = URI(uri_string)

      # disallow creation of redis drains. a malicious user could target
      # the cc redis and overload it. while we could simply exclude
      # "redis://core" from possible drains, one could use the core
      # node's hostname or IP address to get to it.
      if not ["tcp", "udp"].include? uri.scheme 
        logger.warn("An user tried to create a disallowed drain: #{uri}")
        raise Errors::ApiError.new_from_details("StackatoAppDrainInvalidScheme")
      elsif not uri.port.nil? and uri.port < DRAIN_PORT_MIN
        logger.warn("An user tried to create a drain with lesser ports: #{uri}")
        raise Errors::ApiError.new_from_details("StackatoAppDrainPortMax", DRAIN_PORT_MIN)
      elsif uri.scheme.nil?
        raise Errors::ApiError.new_from_details("StackatoAppDrainMissingScheme")
      elsif uri.host.nil?
        raise Errors::ApiError.new_from_details("StackatoAppDrainMissingHost")
      end

      # keep only host:port from URI, the rest must be discarded.
      sanitized_uri = "#{uri.scheme}://#{uri.host}"
      unless uri.port.nil?
        sanitized_uri += ":#{uri.port}"
      end
      return sanitized_uri
    end

    def self.create(app, drain_name, uri, json)
      uri = sanitize_uri uri
    
      uri += "/" unless uri.end_with? "/"
      filter = "apptail.#{app.guid}"
    
      if json
        uri += "?" + URI.encode_www_form("filter" => filter)
      else
        format = "apptail"  # kato config get logyard drainformats/apptail
        uri += "?" + URI.encode_www_form("filter" => filter,
                                         "format" => format)
      end

      drain_id = globally_unique_drain_id(app, drain_name)
      old = Kato::Config.get("logyard", "drains/#{drain_id}")
      unless old.nil?
        raise Errors::ApiError.new_from_details("StackatoAppDrainExists")
      end

      logger.info("Creating a drain #{drain_id} => #{uri}")
      Kato::Config.set("logyard", "drains/#{drain_id}", uri)
    end

    def self.delete(app, drain_name)
      drain_id = globally_unique_drain_id(app, drain_name)
      if Kato::Config.get("logyard", "drains/#{drain_id}").nil?
        raise Errors::ApiError.new_from_details("StackatoAppDrainNotExists")
      end
      logger.info("Deleting drain #{drain_id}")
      Kato::Config.del("logyard", "drains/#{drain_id}")
    end

    def self.delete_all(app)
      drains = Kato::Config.get("logyard", "drains") || []
      drains.each do |drain_id, uri| 
        if drain_id.start_with? "appdrain.#{app.guid}."
          logger.info("Deleting drain #{drain_id}")          
          Kato::Config.del("logyard", "drains/#{drain_id}")
        end
      end
    end

    # Return the total number of drains for this app
    def self.app_drains_count(app)
      Kato::Config.get("logyard", "drains").select { |drain|
        drain.to_s.start_with? "appdrain.#{app.guid}."
      }.count
    end

    def self.list(app)
      drains = Kato::Config.get("logyard", "drains")

      # prefix of drains this app is allowed to touch
      prefix = "appdrain.#{app.guid}."

      # get drain status
      statuses = Kato::Logyard.run_logyard_remote("status", ["-prefix", prefix])
    
      result = {}
      drains.select { |drain_name|
        drain_name.to_s.start_with? prefix
      }.each do |drain_name, uri|
        details = user_uri(drain_name, uri)
        result[drain_name] = details
      end

      # Pick one error, if any, from the list of errors (on all nodes)
      # for each drains. We don't care about showing all errors from the
      # many nodes as that would be flood (however, 'kato drain status'
      # is designed to show all of them).
    
      result.keys.each do |drain_name|
        result[drain_name]["status"] = "Unknown status"
        status = statuses[drain_name]
        if status.nil? or status.empty?
          result[drain_name]["status"] = "Not running"
        else
          notrunning = status.select do |node, node_status|
            node_status["name"] != "RUNNING"
          end
          if notrunning.empty?
            result[drain_name]["status"] = "RUNNING"
          else
            # Some drains are not running.
            witherrors = notrunning.select do |node, node_status|
              node_status["error"]
            end
            unless witherrors.empty?
              status = "Error: " + witherrors.first[1]["error"]
            else
              status = "Unknown error"
            end
            result[drain_name]["status"] = status
          end
        end
      end

      return result.map {|drain_name, details| details}
    end

    private

    # return the user-given drain_name, uri from actual uri
    def self.user_uri(drain_name, uri_string)
      uri = URI.parse(uri_string)
      format = CGI::parse(uri.query)["format"][0]
      json = format.nil? or format == "json"
      uri.query = ''  # remove ?filter= and ?format=
      newuri = uri.to_s.gsub /\?$/, ""
      newname = drain_name.to_s.gsub /^appdrain\.\d+\./, ""
    
      return {
        :name => newname.to_sym,
        :json => json,
        :uri => newuri,
      }
    end

  end
end
