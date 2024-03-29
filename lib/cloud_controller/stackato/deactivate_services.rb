require 'cloud_controller/stackato/config'

module VCAP::CloudController
  class StackatoDeactivateServices
    include VCAP::Errors

    def self.start
      @service_activity_timeout = Kato::Config.get('cloud_controller_ng', 'service_activity_timeout') || 120

      logger.debug2 "Inactive service sweeper started... (active timeout: #{@service_activity_timeout})"

      @deactivate_services_thread ||= nil
      if @deactivate_services_thread
        logger.debug2 "Service expiry thread already active...skipping cycle."
        return
      end

      @deactivate_services_thread  = Thread.new do
        while true
          sleep @service_activity_timeout
          logger.debug2 "Expiring inactive services"
          Service.all.each do |service|
            begin
              next unless service.updated_at
              if (Time.now - service.updated_at) > @service_activity_timeout
                logger.debug2 "Deactivating service #{service.label}-#{service.version}, no gateway activity for #{@service_activity_timeout}) seconds."
                service.active = false
                service.save
              end
            rescue Exception => e
              logger.warn "Unable to deactivate service: #{e.message} #{e.backtrace.inspect}"
            end
          end
        end
      end
    end

    def self.logger
      @@logger ||= Steno.logger("cc.stackato.service_deactivation")
    end
  end
end
