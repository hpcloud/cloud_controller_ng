require 'rubygems'
require 'rbvmomi'

class VSpherePlugin < Plugin

    def platform_name
      "vSphere"
    end

    def handle_command(cmd)
        log "received command: #{cmd}"
    end

    def get_conn
        vx = RbVmomi::VIM
        vx.connect(:host     => get_config['server'],
                   :user     => get_config['user'],
                   :password => get_config['password'],
                   :insecure => get_config['insecure'],
                   :ssl      => get_config['https'],
                   :port     => get_config['port'],
                   :path     => get_config['path'],
                   :ns       => 'urn:vim25',
                   :rev      => '4.0',
                   :debug    => get_config.fetch("debug", false)
                  )
    end

    def get_datastore(dc, name)
      datastore = dc.datastore.find { |ds|
        if ds.info.name == name
          log "Found Datastore #{ds.info.name}, free space: #{ds.summary.freeSpace}"
          datastore = ds
        end
      }
      datastore
    end

    # Grab available hosts and verify their status
    # direct from Vsphere
    def available_hosts(resources, whitelist=[])

      available_hosts_arr = []
      hosts = []

      if resources.is_a? Array
        resources.each do |r|
          r.host.each do |cr|
            hosts <<  cr
          end
        end
      else
        resources.hostFolder.children.each do |h|
          if h.is_a? RbVmomi::VIM::ClusterComputeResource or h.is_a? RbVmomi::VIM::ComputeResource
            h.host.each do |h2|
              hosts << h2
            end
          end
        end
      end

      hosts.each do |h|
        if h.summary.overallStatus != 'red'

          if whitelist.length > 0
            available_hosts_arr.push(h) if whitelist.include? h.name
          else
            available_hosts_arr.push(h)
          end
          #  Useful in a future algorithm rework:
          #  h.summary.quickStats.overallCpuUsage
          #  h.summary.quickStats.overallMemoryUsage
          #  h.vm.length (number of VMs on host)
          #  see HostSystem() API object for more
        end
      end
      return available_hosts_arr
    end

    def scale_up
        vx  = RbVmomi::VIM
        vim = get_conn

        dc = vim.serviceInstance.find_datacenter(get_config['datacenter'])
        if !dc
          log "Invalid datacenter #{get_config['datacenter']} specified in vCenter config"
          return
        end
        vm = dc.find_vm(get_config['template'])
        if !vm
          log "Invalid source VM #{get_config['template']} specified in vCenter config"
          return
        end

        clusters = []
        config_clusters = get_config.fetch('clusters', nil)
        if config_clusters and config_clusters.length > 0
          config_clusters.each do |c|
            clusters <<  dc.find_compute_resource(c)
          end
        end

        resources = dc
        resources = clusters if clusters.length > 0

        use_hosts = available_hosts(resources, get_config.fetch('host_whitelist', []))

        if use_hosts.length < 1
          log "No available vsphere hosts to start instance"
          return
        else
          # Use a host that is not at capacity or incapable
          # Round robin the hosts
          if @host_index.nil?
            @host_index = 0
          elsif @host_index >= use_hosts.length
            @host_index = 0
          else
            @host_index = @host_index + 1
          end

          config_spec = RbVmomi::VIM::VirtualMachineConfigSpec()

          config_spec.numCPUs = get_config['numCPUs'] if get_config['numCPUs']
          config_spec.memoryMB = get_config['memoryMB'] if get_config['memoryMB']

          dest_host = use_hosts[@host_index]
          if dest_host.nil?
            log "No destination host at use_hosts[#{@host_index}]"
            return
          end

          # VM relocation specification
          if get_config['datastores']
            ds = nil
            if get_config['datastores'].kind_of?(Array)
              ds_name = get_config['datastores'].sample
              ds = get_datastore(dc, ds_name)
            else
              ds = get_datastore(dc, get_config['datastores'])
            end

            if ds
              relocate_spec = vx.VirtualMachineRelocateSpec(:datastore => ds,
                                                            :host      => dest_host,
                                                            :pool      => dest_host.parent.resourcePool,
                                                            :transform => 'sparse')
            else
              log "Cannot locate datastore: #{get_config['datastores']}"
              return
            end
          else
            log "Datastore not specified, using the host's default"
            relocate_spec = vx.VirtualMachineRelocateSpec(:datastore => dest_host.datastore[0],
                                                          :pool      => dest_host.parent.resourcePool,
                                                          :transform => 'sparse'
            )
          end

          spec = vx.VirtualMachineCloneSpec(:location => relocate_spec,
                                            :config => config_spec,
                                            :powerOn  => true,
                                            :template => false)

          dest_vm_name = ''
          begin
            dest_vm_name = gen_vm_name
          end while dc.find_vm(dest_vm_name)

          vm_folder = dc.vmFolder

          if get_config['dest_folder']
            folder = dc.vmFolder.traverse(get_config['dest_folder'], RbVmomi::VIM::Folder)
            if folder
              vm_folder = folder
            else
              log "Cannot locate VM folder: #{get_config['dest_folder']}, using default"
            end
          end

          # Need to find a proper :folder argument -- folders are probably
          # per-host, as vm.parent works if you're cloning to the same host but
          # seemingly not otherwise.
          log "Starting a new instance on host: " + dest_host.summary.config.name

          log "Cloning a new VM: #{dest_vm_name} from template #{vm.name}"
          begin
              if @config.fetch("wait_ready", false) == true
                  log "Waiting for #{dest_vm_name} to become ready"
                  vm.CloneVM_Task(:folder => vm_folder, :name => dest_vm_name, :spec => spec).wait_for_completion
                  log "#{dest_vm_name} is now READY"
              else
                  vm.CloneVM_Task(:folder => vm_folder, :name => dest_vm_name, :spec => spec)
              end
          rescue Exception => e
              log " Error cloning vm (#{dest_vm_name}): #{e.message} #{e.backtrace.inspect}"
          end
        end
    end
end
