require 'kato/config'
require 'kato/cluster/license'

module VCAP::CloudController
  class StackatoLicenseHelper
    def self.get_license_accepted(license)
      return false if license.blank?
      # This config value was introduced in stackato 3.5.0
      # To make it backwards compatible with older versions set eula_accepted=true if an admin user
      # exists in the database
      eula_accepted = (Kato::Config.get('cluster', 'eula_accepted') == true)
      if !eula_accepted
        if User.select(nil).where(:admin => true, :active => true).exclude(:username => nil).count > 0
          Kato::Config.set('cluster', 'eula_accepted', true)
          eula_accepted = true
        end
      end
      eula_accepted
    end
  end
end
