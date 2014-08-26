#!/usr/bin/env ruby

$:.unshift(File.expand_path("../../../lib", __FILE__))

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __FILE__)

require "rubygems"
require "bundler/setup"
require "cloud_controller"
require "irb/completion"
require "pry"
require "kato/local/node"
begin
  require File.expand_path("../../../spec/support/bootstrap/db_config.rb", __FILE__)
rescue LoadError
  # db_config.rb does not exist in a release, but a config with a database should exist there.
end

config_yml = File.expand_path("../../../config/cloud_controller.yml", __FILE__)
@config = VCAP::CloudController::Config.new().class.from_file(config_yml)
logger = Logger.new(STDOUT)
db_config = @config.fetch(:db).merge(log_level: :debug)
db_config[:database][:password] = Kato::Config.get("stackato_rest", "db/database/password")

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
