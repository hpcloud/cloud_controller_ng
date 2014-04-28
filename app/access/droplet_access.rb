module VCAP::CloudController
  class DropletAccess < BaseAccess
    def create?(droplet)
      super || droplet.app.space.developers.include?(context.user)
    end

    alias :update? :create?
    alias :delete? :create?
  end
end
