namespace :monitor do
  class Numeric
    def delimited
      self.to_s.delimited
    end
  end
  class String
    def delimited
      # Taken from rails' number_helper.rb: number_to_delimited (MIT-licensed)
      self.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
    end
  end
  desc "Monitor cloud controller for resource usage and restart as necessary"
  task :start do
    require 'clockwork'
    require 'kato/node_process_controller'

    PAGE_SIZE = 4096
    vmsize_limit = Kato::Config.get('cloud_controller_ng', 'resource_monitoring/max_vm_size') || 4 * 1024 ** 3
    rss_limit = Kato::Config.get('cloud_controller_ng', 'resource_monitoring/max_vm_size') || 2 * 1024 ** 3

    BackgroundJobEnvironment.new(config).setup_environment
    logger = Steno.logger("CC.monitor")
    node_id = Kato::Local::Node.get_local_node_id
    controller = Kato::NodeProcessController.new(node_id)
    logger.info "Cloud controller monitoring started, max VmSize #{vmsize_limit.delimited}, max VmRSS #{rss_limit.delimited}"

    Clockwork.every(1.hour, 'cc.monitor.job') do
      next unless controller.controller_running?
      pid = controller.process_pid('cloud_controller_ng')
      open("/proc/#{pid}/statm", 'r') do |file|
        stats = file.read.split
        vmsize, rss = stats[0...2].map { |v| v.to_i * PAGE_SIZE }
        # Update these params on every run to avoid requiring restarting the process on config changes.
        vmsize_limit = Kato::Config.get('cloud_controller_ng', 'resource_monitoring/max_vm_size') || vmsize_limit
        rss_limit = Kato::Config.get('cloud_controller_ng', 'resource_monitoring/max_vm_size') || rss_limit
        msg_tail = "VmSize #{vmsize.delimited}/#{vmsize_limit.delimited}, VmRSS #{rss.delimited}/#{rss_limit.delimited}"
        if vmsize > vmsize_limit || rss > rss_limit
          logger.info("Restarting cloud controller (#{msg_tail})")
          controller.restart_process 'cloud_controller_ng'
        else
          logger.info("Cloud controller using #{msg_tail}")
        end
      end
    end

    Clockwork.run
  end
end
