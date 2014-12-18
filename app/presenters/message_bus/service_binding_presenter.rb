require 'presenters/message_bus/service_instance_presenter'

class ServiceBindingPresenter

  def initialize(service_binding)
    @service_binding = service_binding
  end

  def to_hash
    # xxx: bug 105573:
    # credentials updated from the legacy service gateway now get stored as a string inside the
    # legacy_service_gateway.rb:update_handle function  (see upstream commit dc6df0a).
    # Changing that function to store them as a hash as we did previously throws a Sequel error.
    # This workaround makes sure that the credentials we send out over the message bus are a hash.
    if @service_binding.credentials.is_a? String
      begin
        credentials = eval(@service_binding.credentials)
      rescue
        # Default back to providing the credentials as is if eval'ing fails.
        credentials = @service_binding.credentials
      end
    else
      credentials = @service_binding.credentials
    end
    {
      credentials: credentials,
      options: @service_binding.binding_options || {},
      syslog_drain_url: @service_binding.syslog_drain_url
    }.merge(ServiceInstancePresenter.new(@service_binding.service_instance).to_hash)
  end
end


