require 'kato/cluster/license'

module VCAP::CloudController
  class StackatoClusterConfig
    def self.update_license_info(info, license)
      Kato::Cluster::License.update_license_info(info, license)
    end
  end
end