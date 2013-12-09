# Copyright (c) 2009-2012 VMware, Inc.

require "steno"
require "cloud_controller/stackato/autoscaling/autoscaler"

module VCAP::CloudController
  class << self
    attr_accessor :auto_scaler_respondent
  end

  class AutoScalerRespondent
    attr_reader :logger, :config
    attr_reader :message_bus

    def initialize(config, message_bus)

      @logger = Steno.logger("cc.autoscaling")
      @config = config
      @message_bus = message_bus
      @disabled = false

      if @config[:autoscaling]
        @auto_scaler = AutoScaler.new(@config)
      else
        @logger.warn("Autoscaling disabled, cluster config missing.")
        @disabled = true
      end
    end

    def handle_requests
      message_bus.subscribe("health.scale", :queue => "cc") do |decoded_msg|
        process_scale_operation(decoded_msg)
      end
    end

    def process_scale_operation(msg)
      begin
        @auto_scaler.scale_up if @disabled == false and (msg.fetch("op", false) == "up")
      rescue Exception => e
        @logger.warn "Error processing scale up operation\n#{e.message}\n#{e.backtrace.inspect}"
      end
    end
  end
end
