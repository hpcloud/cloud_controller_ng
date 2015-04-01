require "clockwork"

module VCAP::CloudController
  module Stackato
    class BackgroundJobs
      def initialize(config)
        @config = config
        @logger = Steno.logger("cc.stackato.clock")
      end

      def start
        queue_job('docker_registry.cleanup', VCAP::CloudController::Jobs::Runtime::Stackato::DockerRegistryCleanup, 1.day, "22:00")
        queue_job('monitor', VCAP::CloudController::Jobs::Runtime::Stackato::Monitor, 1.hour)
        Clockwork.run
      end

      private

      def queue_job(name, klass, interval, at=nil)
        Clockwork.every(interval, "#{name}.job", at: at) do |_|
          @logger.info "Queueing #{klass} every #{interval} at #{Time.now}"
          job = klass.new(@config)
          Jobs::Enqueuer.new(job, queue: "cc-generic").enqueue()
        end
      end
    end
  end
end
