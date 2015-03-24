require 'cloud_controller/dea/instances_reporter'
require 'cloud_controller/diego/instances_reporter'

module VCAP::CloudController
  class InstancesReporters
    def initialize(config, diego_client, health_manager_client)
      @config = config
      @diego_client = diego_client
      @health_manager_client = health_manager_client
    end

    def number_of_starting_and_running_instances_for_app(app)
      reporter_for_app(app).number_of_starting_and_running_instances_for_app(app)
    end

    def all_instances_for_app(app)
      reporter_for_app(app).all_instances_for_app(app)
    end

    def crashed_instances_for_app(app)
      reporter_for_app(app).crashed_instances_for_app(app)
    end

    def stats_for_app(app)
      reporter_for_app(app).stats_for_app(app)
    end

    def number_of_starting_and_running_instances_for_apps(apps)
      diego_apps = diego_running_disabled? ? [] : apps.select(&:run_with_diego?)
      dea_apps = apps - diego_apps

      diego_instances = diego_reporter.number_of_starting_and_running_instances_for_apps(diego_apps)
      legacy_instances = legacy_reporter.number_of_starting_and_running_instances_for_apps(dea_apps)
      legacy_instances.merge(diego_instances)
    end

    private

    def diego_running_disabled?
      @diego_running_disabled ||= @config[:diego][:running] == 'disabled'
    end

    def reporter_for_app(app)
      return legacy_reporter if diego_running_disabled?

      app.run_with_diego? ? diego_reporter : legacy_reporter
    end

    def diego_reporter
      @diego_reporter ||= Diego::InstancesReporter.new(@diego_client)
    end

    def legacy_reporter
      @dea_reporter ||= Dea::InstancesReporter.new(@health_manager_client)
    end
  end
end
