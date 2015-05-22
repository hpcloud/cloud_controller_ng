$LOAD_PATH.unshift(File.expand_path('../lib', __FILE__))
$LOAD_PATH.unshift(File.expand_path('../app', __FILE__))

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __FILE__)
require 'bundler/setup'

require 'yaml'
require 'sequel'
require 'steno'
require 'cloud_controller'

def config
  @config ||= begin
    VCAP::CloudController::Config.from_redis
  end
end

Dir['lib/tasks/**/*.rake'].each do |tasks|
  load tasks
end

task default: [:rubocop_autocorrect, :spec]

task :rubocop_autocorrect do
  require 'rubocop'
  cli = RuboCop::CLI.new
  exit_code = cli.run(%w(--auto-correct))
  exit(exit_code) if exit_code != 0
end
