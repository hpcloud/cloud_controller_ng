require 'kato/node_process_controller'

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

module VCAP::CloudController::Jobs::Runtime::Stackato
  class Monitor < Struct.new(:config)
    PAGE_SIZE = 4096
    DEFAULT_THRESHOLD_RATIO = 0.95

    def perform
      check_cc_memory_usage
    end

    def job_name_in_configuration
      :monitor
    end

    def max_attempts
      1 # If the job fails, we can just let it run next hour
    end

    def logger
      @logger ||= Steno.logger('CC.monitor')
    end

    def vmsize_limit
      config[:resource_monitoring][:max_vm_size] || 4 * 1024 ** 3
    end

    def rss_limit
      config[:resource_monitoring][:max_rss_size] || 2 * 1024 ** 3
    end

    def get_threshold_ratio
      threshold_ratio = config[:resource_monitoring].fetch(:threshold_ratio, DEFAULT_THRESHOLD_RATIO)
      msg = nil
      begin
        if threshold_ratio > 1.0
          msg = "Resetting config resource_monitoring/threshold_ratio > 1.0 from #{threshold_ratio} to #{DEFAULT_THRESHOLD_RATIO}"
        elsif threshold_ratio < 0.0
          msg = "Resetting config resource_monitoring/threshold_ratio < 0 from #{threshold_ratio} to #{DEFAULT_THRESHOLD_RATIO}"
        end
      rescue
        msg = "Resetting non-numeric config resource_monitoring/threshold_ratio from #{threshold_ratio} to #{DEFAULT_THRESHOLD_RATIO}"
      end
      if msg
        logger.warn(msg)
        threshold_ratio = DEFAULT_THRESHOLD_RATIO
        config[:resource_monitoring][:threshold_ratio] = threshold_ratio
      end
      return threshold_ratio
    end

    def check_cc_memory_usage
      node_id = Kato::Local::Node.get_local_node_id
      controller = Kato::NodeProcessController.new(node_id)
      return unless controller.controller_running?
      pid = controller.process_pid('cloud_controller_ng')
      begin
        open("/proc/#{pid}/statm", 'r') do |file|
          stats = file.read.split
          vmsize, rss = stats[0...2].map { |v| v.to_i * PAGE_SIZE }
          threshold_ratio = get_threshold_ratio

          msg_tail = "VmSize #{vmsize.delimited}/#{vmsize_limit.delimited}, VmRSS #{rss.delimited}/#{rss_limit.delimited}"
          if vmsize > vmsize_limit * threshold_ratio || rss > rss_limit * threshold_ratio
            if vmsize > vmsize_limit * threshold_ratio
              msg_tail += ", VmSize Limit * threshold(#{threshold_ratio}) = #{(vmsize_limit * threshold_ratio).round.delimited}"
            end
            if rss > rss_limit * threshold_ratio
              msg_tail += ", VmRSS Limit * threshold(#{threshold_ratio}) = #{(rss_limit * threshold_ratio).delimited}"
            end
            logger.info("Restarting cloud controller (#{msg_tail})")
            controller.restart_process 'cloud_controller_ng'
          else
            logger.info("Cloud controller using #{msg_tail}")
          end
        end
      rescue Errno::ENOENT
        logger.error("Can't open /proc/#{pid}/statm: #{$!}.  Skipping cloud-controller memory checking.")
      end
    end

  end
end
