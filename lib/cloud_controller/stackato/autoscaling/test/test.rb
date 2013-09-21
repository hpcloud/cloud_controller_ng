unless Kernel.respond_to?(:require_relative)
  module Kernel
    def require_relative(path)
      require File.join(File.dirname(caller[0]), path.to_str)
    end
  end
end

require 'rubygems'
require 'riot'

context "should require and test autoscaler class" do

  require_relative("../autoscaler")
  opts = {:config_file => (ENV['TEST_CONFIG'] or "./test/test_config.yaml")}

  setup do
      AutoScaler.new(opts)
  end

  asserts("plugins should have loaded") do
      topic.plugins != nil
  end

  asserts("should be at least one plugin present") do
      not topic.plugins.empty?
  end

  asserts("should be able to get the first plugins name") do
      topic.plugins.first.platform_name
  end

  asserts("each plugin should respond to scale up") do
    topic.plugins.each do |plugin|
        raise unless plugin.class.method_defined? :scale_up
    end
  end

  asserts("autoscaler should scale up") do
      topic.scale_up
  end

  asserts("should send an email alert") do
     topic.email_alert
  end

  asserts("should send an general alert") do
     topic.alert({}) == nil
  end

end


