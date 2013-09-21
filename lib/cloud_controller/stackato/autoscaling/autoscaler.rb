require 'yaml'
require 'socket'
require 'timeout'
require 'net/smtp'
require 'steno'
require File.join(File.dirname(Pathname.new(__FILE__).realpath), "./plugin")

class AutoScaler

  attr_accessor :config, :plugins

  def initialize(config)
    @config = config[:autoscaling]
    @logger = Steno.logger("cc.autoscaling")
    @installed_plugins = Set.new
    @this_dir = File.expand_path File.dirname(__FILE__)
    @plugins_dir = File.join @this_dir, "platform-plugins/*.rb"

    load_config

    if @config[:enabled] == true
      Dir[@plugins_dir].each { |f| require f }
      register_plugins
      @logger.info "Loaded #{plugins.length} active autoscaling plugins, #{@installed_plugins.length} available"
      @logger.info "Active auto scaling plugins: #{plugins.map{|p| p.platform_name} }"
    end

    @cooldown_period = config[:cooldown_period] || 60
    @last_scaled_at = Time.now - @cooldown_period

  end

  def register_plugins
    Object.constants.each do |klass|
      const = Kernel.const_get(klass)
      if const.respond_to?(:superclass) and const.superclass == Plugin
        @installed_plugins << const.new(@config)
      end
    end
  end

  def load_config
      config_file = @config.fetch(:config_file, "/s/autoscaling.yaml")
      if File.exist? config_file
        file_config = YAML::load_file(config_file)
        @config = file_config.merge(@config)
      else
        raise "Cannot load autoscaling config file: #{config_file}"
      end

      required_keys = [ 'enabled', 'enabled_plugins' ]
      missing_keys = []

      required_keys.each do |k|
        if not @config[k]
          missing_keys.push k
        end
      end

      if missing_keys.length > 0
        raise "Autoscaling config is missing the following keys: #{missing_keys}"
      end
  end

  def plugins
      enabled_plugins = []
      @installed_plugins.each do |plugin|
          if @config["enabled_plugins"].include? plugin.platform_name
              enabled_plugins.push plugin
          end
      end
      enabled_plugins
  end

  def all_plugins
      @plugin_handler.plugins
  end

  def scale_up
      return if @config["enabled"] == false

      if (Time.now - @last_scaled_at) < @cooldown_period
        @logger.debug "Ignoring scale up request, cooldown_period in effect, #{(@cooldown_period - (Time.now - @last_scaled_at)).round} seconds remaining."
        return
      end

      @last_scaled_at = Time.now

      plugins.each do | plugin |
          begin
              t = Thread.new {
                  Timeout.timeout(@config["scale_op_timeout"]) {
                     begin
                       plugin.scale_up
                     rescue Exception => e
                       plugin.log "ERROR -- Uncaught exception scaling up in #{plugin} plugin"
                       plugin.log "Error Message: #{e.message}"
                       plugin.log "Backtrace: #{e.backtrace.inspect}"
                     end
                  }
              }
              # for test suites, where the calling process is not long
              # running, and will not wait for thread execution to complete
              t.join if @config[:debug] == true

          rescue Exception => e
              plugin.log "ERROR -- Uncaught exception scaling up in #{plugin} plugin"
              plugin.log "Error Message: #{e.message}"
              plugin.log "Backtrace: #{e.backtrace.inspect}"
          end
      end
  end

  def alert(type)
      if @config["alert_email"] and not @config["alert_email"].empty?
          email_alert
      end
  end

  def email_alert(opts={})

      opts[:server]      ||= 'localhost'
      opts[:from]        ||=  "stackato-autoscaler@#{Socket.gethostname}"
      opts[:from_alias]  ||= 'Stackato (Autoscaler)'
      opts[:subject]     ||=  @config["alert_subject"]
      opts[:body]        ||= "A scaling event was processed"

      msg = <<END_OF_MESSAGE
From: #{opts[:from_alias]} <#{opts[:from]}>
To: <#{@config["alert_email"]}>
Subject: #{opts[:subject]}

#{opts[:body]}
END_OF_MESSAGE

      Net::SMTP.start(opts[:server]) do |smtp|
        smtp.send_message msg, opts[:from], @config["alert_email"]
      end
  end
end
