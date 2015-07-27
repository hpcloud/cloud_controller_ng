require 'kato/config'
require 'kato/cluster/license'

module VCAP::CloudController
  class StackatoLicenseHelper
    def self.username_populator
      @@username_populator ||= UsernamePopulator.new(::CloudController::DependencyLocator.instance.username_lookup_uaa_client)
    end

    def self.get_license_accepted(license)
      return false if license.blank?
      # This config value was introduced in stackato 3.5.0
      # To make it backwards compatible with older versions set eula_accepted=true if an admin user
      # exists in the database
      eula_accepted = (Kato::Config.get('cluster', 'eula_accepted') == true)
      if !eula_accepted
        # Gather the list of admin users that have a username.
        users = User.where(:admin => true, :active => true).all
        username_populator.transform(users)
        admin_users_with_username = users.any? do |user|
          !user.username.nil?
        end

        if admin_users_with_username.count > 0
          Kato::Config.set('cluster', 'eula_accepted', true)
          eula_accepted = true
        end
      end
      eula_accepted
    end
  end
end
