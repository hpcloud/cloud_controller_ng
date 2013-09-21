require 'rubygems'
require 'fog'

class HPCSPlugin < Plugin

    def platform_name
      "HPCS"
    end

    def handle_command(cmd)
        log "received command: #{cmd}"
    end

    def get_conn
        Fog::Compute.new(:provider => "HP",
                         :version => get_config["compute"]["api_version"],
                         :hp_avl_zone => get_config["compute"]["zone"],
                         :hp_access_key => get_config["auth"]["access_key"],
                         :hp_secret_key => get_config["auth"]["secret_key"],
                         :hp_tenant_id => get_config["auth"]["tenant_id"]
                         )
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

        user_data = get_config.fetch("user_data", "").pack("m")

        config_drive = get_config.fetch("config_drive", false)
        name = "#{@config["vm_name_prefix"]}-#{(0...8).map{(65+rand(26)).chr}.join}"
        tags = get_config.fetch("tags", {})
        tags[:Name] = name
        tags[:ScaledAt] = Time.now.utc

        log "Requesting a new server instance (#{name}) from template ID: #{get_config["template_id"]}"

        new_server = conn.servers.create(
              :name => name,
              :flavor_id => get_config["flavor_id"],
              :image_id => get_config["template_id"],
              :key_name => get_config["keypair"],
              :security_groups => get_config["security_groups"],
              :tags => get_config.fetch("tags", {}),
              :config_drive => config_drive,
              :user_data_encoded => user_data,
              :personality => personality
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
