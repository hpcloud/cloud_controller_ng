desc 'Runs all redundant config checks'
task stackato: %w[
              stackato:find_redundant_permissions
              stackato:find_redundant_updaters
            ]

namespace :stackato do
  task :find_redundant_permissions do
    CloudController::RedundantConfigCheck.find_redundant_permissions
  end

  task :find_redundant_updaters do
    CloudController::RedundantConfigCheck.find_redundant_updaters
  end

  class CloudController::RedundantConfigCheck
    require 'cloud_controller/stackato/config'

    # Which config parameters are returned by the API.
    PERMISSIONS = YAML.load_file(File.join(File.dirname(__FILE__), "..", "..", "config", "stackato", "config_permissions.yml"))["processes"]

    # should only have config_permissions for existing config
    def self.find_redundant_permissions
      def self.test_config_exists(component_id, path, value)
        if value.is_a? Hash
          value.each_pair do |k, v|
            test_config_exists(component_id, File.join(path, k), v)
          end
        else
          if Kato::Config.get(component_id, path).nil?
            $stderr.puts "WARNING: Stackato redundant config permission: #{component_id} #{path}"
          end
        end
      end
      PERMISSIONS.each_pair do |component_id, value|
        test_config_exists(component_id, "/", value)
      end
    end

    # should only have config update methods for permission RW
    def self.find_redundant_updaters
      VCAP::CloudController::StackatoConfig.new("all").private_methods.sort.each do |method_sym|
        method_name = method_sym.to_s
        next unless method_name.start_with? "_update__"
        next if method_name == "_update__logging"
        match = (/^_update__(.*)__(.*)$/.match(method_name) || /^_update__(.*)$/.match(method_name))
        component_id = match[1]
        key = match[2]
        if Kato::Config.get(component_id, key).nil?
          $stderr.puts "WARN Stackato redundant config updater: #{method_name}"
        end
      end
    end
  end
end