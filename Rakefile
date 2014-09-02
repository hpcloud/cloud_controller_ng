$:.unshift(File.expand_path("../lib", __FILE__))
$:.unshift(File.expand_path("../app", __FILE__))

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __FILE__)
require "bundler/setup"

require "yaml"
require "sequel"
require "steno"
require "cloud_controller"

def config
  @config ||= begin
    VCAP::CloudController::Config.from_redis
  end
end

Dir["lib/tasks/**/*.rake"].each do |tasks|
  load tasks
end

task default: [:rubocop, :spec]
