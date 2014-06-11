namespace :buildpacks do

  desc "Install/Update buildpacks"
  task :install do
    buildpacks = config[:install_buildpacks]
    BackgroundJobEnvironment.new(config).setup_environment
    VCAP::CloudController::InstallBuildpacks.new(config).install(buildpacks)
  end

  task :install_one do
    buildpacks = ['name' => ENV['BUILDPACK_NAME'], 'package' => ENV['BUILDPACK_PACKAGE']]
    BackgroundJobEnvironment.new(config).setup_environment
    VCAP::CloudController::InstallBuildpacks.new(config).install(buildpacks)
  end
end