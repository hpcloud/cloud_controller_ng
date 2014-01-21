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

VCAP::CloudController::DB.load_models(db_config, logger)
VCAP::CloudController::Config.configure_components(@config)

if ENV["RACK_ENV"] == "development"
  $:.unshift(File.expand_path("../../../spec/support", __FILE__))
  require "machinist/sequel"
  require "machinist/object"
  require "fakes/blueprints"
end

module VCAP::CloudController
  binding.pry :quiet => true
end
