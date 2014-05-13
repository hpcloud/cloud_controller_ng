$:.unshift(File.expand_path("../lib", __FILE__))
$:.unshift(File.expand_path("../app", __FILE__))

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
