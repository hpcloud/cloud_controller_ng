#!/usr/bin/env ruby

$:.unshift(File.expand_path("../../../lib", __FILE__))

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __FILE__)

require "rubygems"
require "bundler/setup"
require "cloud_controller"
require "irb/completion"
require "pry"

@config = VCAP::CloudController::Config.new()
logger = Logger.new(STDOUT)

db_config = @config.fetch(:db).merge(log_level: :debug)

VCAP::CloudController::DB.connect(logger, db_config, db_config)

module VCAP::CloudController
  binding.pry :quiet => true
end
