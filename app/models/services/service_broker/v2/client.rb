module VCAP::CloudController
  class ServiceBroker::V2::Client
    def initialize(attrs)
      @http_client = ServiceBroker::V2::HttpClient.new(attrs)
    end

    def catalog
      @http_client.catalog
    end

    def provision(instance)
      response = @http_client.provision(
        instance.guid,
        instance.service_plan.broker_provided_id,
        instance.space.organization.guid,
        instance.space.guid
      )

      instance.dashboard_url = response['dashboard_url']

      # DEPRECATED, but needed because of not null constraint
      instance.credentials = {}
    end

    def bind(binding)
      response = @http_client.bind(binding.guid, binding.service_instance.guid)

      binding.credentials = response['credentials']
    end

    def unbind(binding)
      @http_client.unbind(binding.guid)
    end

    def deprovision(instance)
      @http_client.deprovision(instance.guid)
    end
  end
end
