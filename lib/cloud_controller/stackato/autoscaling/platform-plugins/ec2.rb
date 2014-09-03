require 'rubygems'
require 'fog'

class EC2Plugin < Plugin

    def platform_name
      "EC2"
    end

    def handle_command(cmd)
        log "received command: #{cmd}"
    end

    def get_conn
        Fog::Compute.new(:provider => "AWS",
                         :region => get_config["compute"]["region"],
                         :aws_access_key_id => get_config["auth"]["access_key"],
                         :aws_secret_access_key => get_config["auth"]["secret_key"]
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

        user_data = get_config.fetch("user_data", nil)
        user_data.pack('m') if user_data

        config_drive = get_config.fetch("config_drive", false)
        name = "#{@config["vm_name_prefix"]}-#{(0...8).map{(65+rand(26)).chr}.join}"

        tags = get_config.fetch("tags", {})
        tags[:Name] = name
        tags[:ScaledAt] = Time.now.utc

        log "Requesting a new server instance (#{name}) from template ID: #{get_config["instance_type"]}"

        new_server = conn.servers.create(
              :name => name,
              :flavor_id => get_config["instance_type"],
              :image_id => get_config["template_id"],
              :key_name => get_config["keypair"],
              :security_group_ids => get_config["security_group_ids"],
              :user_data_encoded => user_data,
              :tags => tags
        )

        log "Scaled a new instance with server ID: #{new_server.id}"

        if @config.fetch("wait_ready", false) == true
            new_server.wait_for { ready? }
            log "#{new_server.id} is now READY"
        end

        true
    end
end
