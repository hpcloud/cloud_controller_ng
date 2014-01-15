
require 'cloud_controller/stackato/app_pool'

module VCAP::CloudController
  class << self
    attr_accessor :dea_respondent
  end

  class DeaRespondent
    attr_accessor :logger

    attr_reader :config
    attr_reader :message_bus

    CRASH_EVENT_QUEUE = "crash_event_registration".freeze

    def initialize(message_bus)
      @logger = Steno.logger("cc.dea_respondent")
      @message_bus = message_bus
    end

    def start
      message_bus.subscribe("droplet.exited", :queue => CRASH_EVENT_QUEUE) do |decoded_msg|
        process_droplet_exited_message(decoded_msg)
      end

      message_bus.subscribe("dea.heartbeat") do |heartbeat_message|
        process_dea_heartbeat_message(heartbeat_message)
      end
    end

    def crashed_app?(decoded_message)
      decoded_message["reason"] && decoded_message["reason"].downcase == "crashed"
    end

    def process_droplet_exited_message(decoded_message)
      app_guid = decoded_message["droplet"]

      app = App[:guid => app_guid]

      if app && crashed_app?(decoded_message)
        Event.create_app_exit_event(app, decoded_message)

        AppEvent.create(
          app_id: app.id,
          instance_guid: decoded_message["instance"],
          instance_index: decoded_message["index"],
          exit_status: decoded_message["exit_status"],
          exit_description: decoded_message["exit_description"],
          timestamp: Time.now
        )
      end
    end

    def process_dea_heartbeat_message(heartbeat_message)
      VCAP::CloudController::StackatoAppPool.add_dea_heartbeat heartbeat_message
    end
  end
end
