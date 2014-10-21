namespace :monitor do
  desc "Monitor cloud controller for resource usage and restart as necessary"
  task :start do
    require 'clockwork'
    require 'cloud_controller/stackato/monitor'

    BackgroundJobEnvironment.new(config).setup_environment
    monitor = VCAP::CloudController::Stackato::Monitor.new
    monitor.start
  end
end
