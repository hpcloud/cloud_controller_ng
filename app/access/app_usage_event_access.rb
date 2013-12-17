module VCAP::CloudController
  class AppUsageEventAccess < BaseAccess
    def index?(object_class)
      context.roles.admin?
    end
  end
end
