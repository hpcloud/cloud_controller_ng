require 'rubygems'
require 'fog'

class OpenStackPlugin < Plugin

    def platform_name
      "OpenStack"
    end

    def handle_command(cmd)
        log "received command: #{cmd}"
    end

    def get_conn
        Fog::Compute.new({
          :provider => 'OpenStack',
          :openstack_api_key => get_config["password"],
          :openstack_username => get_config["username"],
          :openstack_auth_url => get_config["auth_url"],
          :openstack_tenant => get_config["tenant_id"]
        })
    end

    def scale_up
        conn = get_conn

        servers = conn.servers
        active = []
        servers.each do | s |
            if s.state == "ACTIVE"
                active.push s
            end
        end if servers
        log "Active servers currently in the configured deployment platform: #{servers.size}"

        personality = get_config.fetch("personality", [])

        user_data = get_config.fetch("user_data", nil)
        user_data.pack('m') if user_data

        config_drive = get_config.fetch("config_drive", false)
        name = "#{@config["vm_name_prefix"]}-#{(0...8).map{(65+rand(26)).chr}.join}"

        metadata = get_config.fetch("metadata", {})
        metadata["Name"] = name
        metadata["ScaledAt"] = Time.now.utc
        metadata["ScaledBy"] = get_host

        flavor_id = nil
        flavors = conn.list_flavors.body['flavors']
        flavors.each do | f |
             flavor_id = f["id"] if f["name"] == get_config["flavor"]
        end
        raise "Unknown flavor: #{get_config["flavor"]}" unless flavor_id

        log "Requesting a new server instance (#{name}) from template ID: #{get_config["template_id"]}"
        p get_config["metadata"]
        new_server = conn.servers.create(
              :name => name,
              :flavor_ref => flavor_id,
              :image_ref => get_config["template_id"],
              :key_name => get_config["keypair"],
              :security_groups => get_config["security_groups"],
              :user_data_encoded => user_data,
              :metadata => metadata
        )

        log "Scaled a new instance with server ID: #{new_server.id}"

        if @config.fetch("wait_ready", false) == true
            log "Waiting for #{new_server.id} to become ready"
            new_server.wait_for { ready? }
            log "#{new_server.id} is now READY"
        end

        true
    end
end
