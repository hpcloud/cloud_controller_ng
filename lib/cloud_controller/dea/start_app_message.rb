module VCAP::CloudController
  module Dea
    class StartAppMessage < Hash
      def initialize(app, index, config, blobstore_url_generator, docker_registry)
        super()

        self[:droplet]        = app.guid
        self[:name]           = app.name
        self[:uris]           = app.uris
        self[:prod]           = app.production
        self[:sha1]           = app.droplet_hash
        self[:executableFile] = "deprecated"
        self[:executableUri]  = blobstore_url_generator.droplet_download_url(app)
        self[:version]        = app.version

        self[:services] = app.service_bindings.map do |sb|
          ServiceBindingPresenter.new(sb).to_hash
        end

        self[:limits] = {
            mem:  app.memory,
            disk: app.disk_quota,
            fds:  app.file_descriptors,
            allow_sudo: app.allow_sudo?
        }

        self[:allowed_repos] = config[:allowed_repos]
        self[:cc_partition]         = config[:cc_partition]
        self[:env]                  = (app.environment_json || {}).map { |k, v| "#{k}=#{v}" }
        self[:console]              = app.console
        self[:debug]                = app.debug
        self[:docker_image]         = app.docker_image
        self[:docker_registry]      = docker_registry
        self[:start_command]        = app.command
        self[:health_check_timeout] = app.health_check_timeout
        self[:sso_enabled] = app.sso_enabled
        self[:sso_credentials] = app.routes.collect do |route|
                      {
                        fqdn: route.fqdn,
                        client_id: route.client_id,
                        client_secret: route.client_secret
                      }
                    end
        self[:min_cpu_threshold] = app.min_cpu_threshold
        self[:max_cpu_threshold] =  app.max_cpu_threshold
        self[:min_instances] = app.min_instances
        self[:max_instances] =  app.max_instances
        self[:autoscale_enabled] =  app.autoscale_enabled
        self[:vcap_application]     = app.vcap_application
        self[:index]                = index
        self[:egress_network_rules] = EgressNetworkRulesPresenter.new(app.space.security_groups).to_array
      end

      def has_app_package?
        return !self[:executableUri].nil?
      end
      def has_docker_image?
        return !self[:docker_image].nil?
      end
    end
  end
end
