
module VCAP::CloudController
  class StackatoLicenseHelper
    def self.get_license_accepted(license)
      return false if license.blank?
      return User.select(nil).
                  where(:admin => true, :active => true).
                  exclude(:username => nil).
                  count > 0
    end
  end
end
