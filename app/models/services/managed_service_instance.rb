require 'vcap/request'

module VCAP::CloudController
  class ManagedServiceInstance < ServiceInstance
    class MissingServiceAuthToken < StandardError; end
    class ServiceGatewayError < StandardError; end

    class NGServiceGatewayClient
      attr_accessor :service, :token, :service_id

      def initialize(service, service_id)
        @service = service
        @token   = service.service_auth_token
        @service_id = service_id
        unless token
          raise MissingServiceAuthToken, "ServiceAuthToken not found for service #{service}"
        end
      end

      def create_snapshot(name)
        payload = VCAP::Services::Api::CreateSnapshotV2Request.new(:name => name).encode
        response = do_request(:post, payload)
        VCAP::Services::Api::SnapshotV2.decode(response)
      end

      def enum_snapshots
        list = VCAP::Services::Api::SnapshotListV2.decode(do_request(:get))
        list.snapshots.collect{|e| VCAP::Services::Api::SnapshotV2.new(e) }
      end

      private

      def do_request(method, payload=nil)
        client = HTTPClient.new
        u = URI.parse(service.url)
        u.path = "/gateway/v2/configurations/#{service_id}/snapshots"

        response = client.public_send(method, u,
          :header => { VCAP::Services::Api::GATEWAY_TOKEN_HEADER => token.token,
            "Content-Type" => "application/json"
          },
          :body   => payload)
        if response.ok?
          response.body
        else
          raise ServiceGatewayError, "Service gateway upstream failure, responded with #{response.status}: #{response.body}"
        end
      end
    end

    class << self
      def gateway_client_class
        @gateway_client_class || VCAP::Services::Api::ServiceGatewayClient
      end

      def gateway_client_class=(klass)
        raise ArgumentError, "gateway_client_class must not be nil" unless klass
        @gateway_client_class = klass
      end
    end

    many_to_one :service_plan

    default_order_by  :id

    export_attributes :name, :credentials, :service_plan_guid,
      :space_guid, :gateway_data, :dashboard_url, :type

    import_attributes :name, :service_plan_guid,
      :space_guid, :gateway_data

    strip_attributes  :name

    def validate
      super
      validates_presence :service_plan
      check_quota
    end

    def after_create
      super
      ServiceCreateEvent.create_from_service_instance(self)
    end

    def after_destroy
      super
      deprovision_on_gateway
      ServiceDeleteEvent.create_from_service_instance(self)
    end

    def as_summary_json
      {
        :guid => guid,
        :name => name,
        :bound_app_count => service_bindings_dataset.count,
        :dashboard_url => dashboard_url,
        :service_plan => {
          :guid => service_plan.guid,
          :name => service_plan.name,
          :service => {
            :guid => service.guid,
            :label => service.label,
            :provider => service.provider,
            :version => service.version,
          }
        }
      }
    end

    def check_quota
      if space
        unless service_plan
          errors.add(:space, :quota_exceeded)
          return
        end

        quota_errors = space.organization.check_quota?(service_plan)
        unless quota_errors.empty?
          errors.add(quota_errors[:type], quota_errors[:name])
        end
      end
    end

    def gateway_data=(val)
      str = Yajl::Encoder.encode(val)
      super(str)
    end

    def gateway_data
      val = super
      val = Yajl::Parser.parse(val) if val
      val
    end

    def requester
      VCAP::Services::Api::SynchronousHttpRequest
    end

    def service_gateway_client(plan = service_plan)
      @client ||= begin
        raise InvalidServiceBinding.new("no service_auth_token") unless plan.service.service_auth_token

        self.class.gateway_client_class.new(
          plan.service.url,
          plan.service.service_auth_token.token,
          plan.service.timeout,
          VCAP::Request.current_id,
        )
      end
    end

    def service
      service_plan.service
    end

    def deprovision_on_gateway
      service_gateway_client.unprovision(:service_id => gateway_name)
    rescue => e
      logger.error "deprovision failed #{e}"
    end

    def create_snapshot(name)
      NGServiceGatewayClient.new(service, gateway_name).create_snapshot(name)
    end

    def enum_snapshots
      NGServiceGatewayClient.new(service, gateway_name).enum_snapshots
    end

    def snapshot_details(sid)
      service_gateway_client.snapshot_details(:service_id => gateway_name, :snapshot_id => sid)
    end

    def rollback_snapshot(sid)
      service_gateway_client.rollback_snapshot(:service_id => gateway_name, :snapshot_id => sid)
    end

    def delete_snapshot(sid)
      service_gateway_client.delete_snapshot(:service_id => gateway_name, :snapshot_id => sid)
    end

    def serialized_url(sid)
      service_gateway_client.serialized_url(:service_id => gateway_name, :snapshot_id => sid)
    end

    def create_serialized_url(sid)
      service_gateway_client.create_serialized_url(:service_id => gateway_name, :snapshot_id => sid)
    end

    def import_from_url(req)
      service_gateway_client.import_from_url(:service_id => gateway_name, :msg => req)
    end

    def job_info(job_id)
      service_gateway_client.job_info(:service_id => gateway_name, :job_id => job_id)
    end

    def logger
      @logger ||= Steno.logger("cc.models.service_instance")
    end

    def unbind_on_gateway(service_binding)
      return unless service_gateway_client
      service_gateway_client.unbind(
        :service_id      => self.gateway_name,
        :handle_id       => service_binding.gateway_name,
        :binding_options => service_binding.binding_options,
      )
    rescue => e
      logger.error "unbind failed #{e}"
    end

    def bind_on_gateway(service_binding)
      logger.debug "binding service on gateway for #{service_binding.guid}"

      service = service_plan.service

      gw_attrs = service_gateway_client.bind(
        :service_id => gateway_name,
        # TODO: we shouldn't still be using this compound label
        :label      => "#{service.label}-#{service.version}",
        :email      => VCAP::CloudController::SecurityContext.current_user_email,
        :binding_options => service_binding.binding_options,
      )

      logger.debug "binding response for #{service_binding.guid} #{gw_attrs.inspect}"

      service_binding.gateway_name = gw_attrs.service_id
      service_binding.gateway_data = gw_attrs.configuration
      service_binding.credentials  = gw_attrs.credentials
      service_binding.syslog_drain_url  = gw_attrs.syslog_drain_url
    end

    def bindable?
      service_plan.bindable?
    end

    def tags
      service.tags
    end
  end
end
