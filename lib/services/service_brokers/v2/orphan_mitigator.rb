require 'jobs/services/delete_orphaned_binding'
require 'jobs/services/delete_orphaned_instance'

module VCAP::Services
  module ServiceBrokers
    module V2
      class OrphanMitigator
        def cleanup_failed_provision(client_attrs, service_instance)
          deprovision_job = VCAP::CloudController::Jobs::Services::DeleteOrphanedInstance.new(
            'service-instance-deprovision',
            client_attrs,
            service_instance.guid,
            service_instance.service_plan.guid
          )

          opts = { queue: 'cc-generic', run_at: Delayed::Job.db_time_now }
          VCAP::CloudController::Jobs::Enqueuer.new(deprovision_job, opts).enqueue
        end

        def cleanup_failed_bind(client_attrs, service_binding)
          unbind_job = VCAP::CloudController::Jobs::Services::DeleteOrphanedBinding.new(
            'service-instance-unbind',
            client_attrs,
            service_binding.guid,
            service_binding.service_instance.guid,
            service_binding.app.guid
          )

          opts = { queue: 'cc-generic', run_at: Delayed::Job.db_time_now }
          VCAP::CloudController::Jobs::Enqueuer.new(unbind_job, opts).enqueue
        end
      end
    end
  end
end
