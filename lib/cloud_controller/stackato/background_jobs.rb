require "clockwork"

module VCAP::CloudController
  module Stackato
    class BackgroundJobs
      def initialize(config)
        @config = config
        @logger = Steno.logger("cc.stackato.clock")
      end

      def start
        queue_job('docker_registry.cleanup', :DockerRegistryCleanup,
                  at: "#{(0...24).to_a.sample}:00")
        queue_job('monitor', :Monitor,
                  interval: 1.hour)
        Clockwork.run
      end

      private

      def queue_job(name, class_name, opts={})
        opts = {interval: 1.day, at: nil, queue: "cc-generic"}.merge(opts)
        klass = VCAP::CloudController::Jobs::Runtime::Stackato.const_get(class_name)
        Clockwork.every(opts[:interval], "#{:name}.job", at: opts[:at]) do |_|
          @logger.info "Queueing #{klass} every #{opts[:interval]} at #{Time.now}"
          job = klass.new(@config)
          Jobs::Enqueuer.new(job, queue: opts[:queue]).enqueue()
        end
      end
    end
  end
end
