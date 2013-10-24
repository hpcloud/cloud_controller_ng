
module VCAP; end

require 'cloud_controller/stackato/config'

PERMISSIONS = VCAP::CloudController::StackatoConfig::PERMISSIONS

# should only have config_permissions for existing config
def find_redundant_permissions
  def test_config_exists(component_id, path, value)
    if value.is_a? Hash
      value.each_pair do |k, v|
        test_config_exists(component_id, File.join(path, k), v)
      end
    else
      if Kato::Config.get(component_id, path).nil?
        puts "redundant: #{component_id} #{path}"
      end
    end
  end
  PERMISSIONS.each_pair do |component_id, value|
    test_config_exists(component_id, "/", value)
  end
end

# should only have config update methods for permission RW
def find_redundant_updaters
  # TODO:Stackato: implement me
end

find_redundant_permissions
