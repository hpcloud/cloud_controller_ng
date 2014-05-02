require 'kato/cluster/license'

module VCAP::CloudController
  class StackatoClusterConfig
    def self.update_license_info(info, license)
      if VCAP::CloudController::SecurityContext.current_user
        Kato::Cluster::License.update_license_info(info, license)
      end
    end
  end
end