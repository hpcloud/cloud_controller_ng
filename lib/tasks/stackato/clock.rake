namespace :stackato_clock do
  desc "Start Stackato recurring tasks"
  task :start do
    require "cloud_controller/stackato/background_jobs"

    BackgroundJobEnvironment.new(config).setup_environment
    clock = VCAP::CloudController::Stackato::BackgroundJobs.new(config)
    clock.start
  end
end
