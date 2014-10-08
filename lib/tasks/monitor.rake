namespace :monitor do
  class Numeric
    def delimited
      self.to_s.delimited
    end
  end
  class String
    def delimited
      # Taken from rails' number_helper.rb: number_to_delimited (MIT-licensed)
      parts = self.split('.', 2)
      parts[0].gsub!(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
      parts.join('.')
    end
  end
  
  def check_threshold_ratio(threshold_ratio, default_threshold_ratio, logger)
    msg = nil
    begin
      if threshold_ratio > 1.0
        msg = "Resetting config resource_monitoring/threshold_ratio > 1.0 from #{threshold_ratio} to #{default_threshold_ratio}"
      elsif threshold_ratio < 0.0
        msg = "Resetting config resource_monitoring/threshold_ratio < 0 from #{threshold_ratio} to #{default_threshold_ratio}"
      end
    rescue
      msg = "Resetting non-numeric config resource_monitoring/threshold_ratio from #{threshold_ratio} to #{default_threshold_ratio}"
    end
    if msg
      logger.warn(msg)
      threshold_ratio = default_threshold_ratio
      Kato::Config.set('cloud_controller_ng', 'resource_monitoring/max_rss_size', threshold_ratio)
    end
    return threshold_ratio
  end
  
  desc "Monitor cloud controller for resource usage and restart as necessary"
  task :start do
    require 'clockwork'
    require 'kato/node_process_controller'

    PAGE_SIZE = 4096
    DEFAULT_THRESHOLD_RATIO = 0.95
    vmsize_limit = Kato::Config.get('cloud_controller_ng', 'resource_monitoring/max_vm_size') || 4 * 1024 ** 3
    rss_limit = Kato::Config.get('cloud_controller_ng', 'resource_monitoring/max_rss_size') || 2 * 1024 ** 3
    threshold_ratio = Kato::Config.get('cloud_controller_ng', 'resource_monitoring/threshold_ratio') || DEFAULT_THRESHOLD_RATIO

    BackgroundJobEnvironment.new(config).setup_environment
    logger = Steno.logger("CC.monitor")
    node_id = Kato::Local::Node.get_local_node_id
    controller = Kato::NodeProcessController.new(node_id)
    logger.info "Cloud controller monitoring started, max VmSize #{vmsize_limit.delimited}, max VmRSS #{rss_limit.delimited}"

    Clockwork.every(1.hour, 'cc.monitor.job') do
      next unless controller.controller_running?
      pid = controller.process_pid('cloud_controller_ng')
      begin
        open("/proc/#{pid}/statm", 'r') do |file|
          stats = file.read.split
          vmsize, rss = stats[0...2].map { |v| v.to_i * PAGE_SIZE }
          # Update these params on every run to avoid requiring restarting the process on config changes.
          vmsize_limit = Kato::Config.get('cloud_controller_ng', 'resource_monitoring/max_vm_size') || vmsize_limit
          rss_limit = Kato::Config.get('cloud_controller_ng', 'resource_monitoring/max_rss_size') || rss_limit
          threshold_ratio =
              check_threshold_ratio(Kato::Config.get('cloud_controller_ng', 'resource_monitoring/threshold_ratio') ||
                                                  threshold_ratio,
                                    DEFAULT_THRESHOLD_RATIO, logger)
          
          msg_tail = "VmSize #{vmsize.delimited}/#{vmsize_limit.delimited}, VmRSS #{rss.delimited}/#{rss_limit.delimited}"
          if vmsize > vmsize_limit * threshold_ratio || rss > rss_limit * threshold_ratio
            if vmsize > vmsize_limit * threshold_ratio
              msg_tail += ", VmSize Limit * threshold(#{threshold_ratio} = #{(vmsize_limit * threshold_ratio).round.delimited}"
            end
            if rss > rss_limit * threshold_ratio
              msg_tail += ", VmRSS Limit * threshold(#{threshold_ratio} = #{(rss_limit * threshold_ratio).delimited}"
            end
            logger.info("Restarting cloud controller (#{msg_tail})")
            controller.restart_process 'cloud_controller_ng'
          else
            logger.info("Cloud controller using #{msg_tail}")
          end
        end
      rescue Errno::ENOENT
        logger.error("Can't open /proc/#{pid}/statm: #{$!}.  Skipping cloud-controller memory checking")
      end
    end

    Clockwork.run
  end
end
