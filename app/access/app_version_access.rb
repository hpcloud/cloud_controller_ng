module VCAP::CloudController
  class AppVersionAccess < BaseAccess
    def create?(version)
      super || version.app.space.developers.include?(context.user)
    end

    alias :update? :create?
    alias :delete? :create?
  end
end
