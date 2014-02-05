require 'rubygems'
require 'fog'
require 'uri'

class CloudStackPlugin < Plugin

    def platform_name
      "CloudStack"
    end

    def handle_command(cmd)
        log "received command: #{cmd}"
    end

    def get_conn
      @conn ||= begin
        cloudstack_uri = URI.parse(get_config.fetch("api_endpoint"))
        Fog::Compute.new(:provider => :cloudstack,
                         :cloudstack_api_key => get_config["api_key"],
                         :cloudstack_secret_access_key => get_config["secret_key"],
                         :cloudstack_host => cloudstack_uri.host,
                         :cloudstack_port => cloudstack_uri.port,
                         :cloudstack_path => cloudstack_uri.path,
                         :cloudstack_scheme => cloudstack_uri.scheme
                         )
      end
    end

    def create_server_definition
      definition = {}

      definition['name'] = definition['displayname'] = gen_vm_name
      definition['zoneid'] = get_config['zone_id']
      definition['templateid'] = get_config['template_id']
      definition['serviceofferingid'] = get_config['flavor_id']

      if get_config['disk_offering_id']
        definition['diskofferingid'] = get_config['disk_offering_id']
      end

      if get_config['security_group_ids']
        definition['securitygroupids'] = get_config['security_group_ids']
      end

      if get_config['network_ids']
        definition['networkids'] = get_config['network_ids']
      end

      definition
    end

    def scale_up
        @conn = get_conn
        deployment = @conn.deploy_virtual_machine(create_server_definition)
        deployment_id = deployment['deployvirtualmachineresponse'].fetch('jobid')

        server_status = @conn.query_async_job_result('jobid' => deployment_id)
        log "Started a new instance with server ID: #{deployment['deployvirtualmachineresponse'].fetch('id')}"

        if @config.fetch("wait_ready", false) == true
          log "Waiting for server to start..."
          while server_status['queryasyncjobresultresponse'].fetch('jobstatus') == 0
            log "Server status: #{server_status['queryasyncjobresultresponse'].fetch('jobstatus')}"
            sleep 2
            server_status = @conn.query_async_job_result('jobid' => deployment_id)
          end
        end

        if server_status['queryasyncjobresultresponse'].fetch('jobstatus') == 2
          log "ERROR: Failed to start server: #{server_status['queryasyncjobresultresponse'].fetch('jobresult').fetch('errortext')}"
          return false
        end

        if server_status['queryasyncjobresultresponse'].fetch('jobstatus') == 1
          server = server_status['queryasyncjobresultresponse']['jobresult']['virtualmachine']
          log "Auto scaled server: #{server['displayname']} is ready"
        end

        true
    end
end
