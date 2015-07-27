
module VCAP::CloudController
  class StackatoLicenseHelper
    def self.username_populator
      @@username_populator ||= UsernamePopulator.new(::CloudController::DependencyLocator.instance.username_lookup_uaa_client)
    end

    def self.get_license_accepted(license)
      return false if license.blank?

      # Gather the list of admin users that have a username.
      users = User.where(:admin => true, :active => true).all
      username_populator.transform(users)
      users.any? do |user|
        !user.username.nil?
      end
    end
  end
end
