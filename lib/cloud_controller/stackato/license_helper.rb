
module VCAP::CloudController
  class StackatoLicenseHelper
    def self.get_license_accepted(license)
      return false if license.blank?
      #users = User.select(:username).
      #             where(:admin => true, :active => true, !:username => nil)...
      #XXX How do we talk about non-nil in pure Sequel query syntax?
      return !! User.select(:username).
                     where(:admin => true, :active => true).
                     find {|user| !user.username.nil? }
    end
  end
end
