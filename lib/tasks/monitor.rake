namespace :monitor do
  desc "Monitor cloud controller for resource usage and restart as necessary"
  task :start do
    require 'clockwork'
    require 'kato/node_process_controller'

    PAGE_SIZE = 4096
    VMSIZE_LIMIT = Kato::Config.get('cloud_controller_ng', 'resource_monitoring/max_vm_size') || 4 * 1024 ** 3
    RSS_LIMIT = Kato::Config.get('cloud_controller_ng', 'resource_monitoring/max_vm_size') || 2 * 1024 ** 3

    BackgroundJobEnvironment.new(config).setup_environment
    logger = Steno.logger("CC.monitor")
    node_id = Kato::Local::Node.get_local_node_id
    controller = Kato::NodeProcessController.new(node_id)
    logger.info "Cloud controller monitoring started, max VmSize #{VMSIZE_LIMIT}, max VmRSS #{RSS_LIMIT}"

    Clockwork.every(1.hour, 'cc.monitor.job') do
      next unless controller.controller_running?
      pid = controller.process_pid('cloud_controller_ng')
      open("/proc/#{pid}/statm", 'r') do |file|
        stats = file.read.split
        vmsize, rss = stats[0...2].map { |v| v.to_i * PAGE_SIZE }
        if vmsize > VMSIZE_LIMIT || rss > RSS_LIMIT
          logger.info("Restarting cloud controller (VmSize #{vmsize}, VmRSS #{rss})")
          controller.restart_process 'cloud_controller_ng'
        else
          logger.info("Cloud controller using VmSize #{vmsize}, VmRSS #{rss}")
        end
      end
    end

    Clockwork.run
  end
end
