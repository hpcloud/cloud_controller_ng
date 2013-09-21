require 'set'
require 'socket'

class Plugin

  attr_accessor :plugins, :load, :config, :platform_name, :log

  def initialize(config)
    @config = config
  end

  def get_config
    @config["platform_config"][platform_name]
  end

  def self.plugins
    @plugins
  end

  def log(msg)
    p "Auto Scaling::#{platform_name}: #{msg}"
  end

  def get_host
      Socket.gethostname
  end

  def gen_vm_name
    "#{@config["vm_name_prefix"]}-#{(0...8).map{(65+rand(26)).chr}.join}"
  end



end
