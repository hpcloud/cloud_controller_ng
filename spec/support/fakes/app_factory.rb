module VCAP
  module CloudController
    class AppFactory
      def self.make(attributes={})
        defaults = {
            droplet_hash: Sham.guid,
            package_hash: Sham.guid,
            metadata: {},
        }
        attributes = defaults.merge(attributes)

        app = VCAP::CloudController::App.make(attributes)
        if !app.updated_at
          app.updated_at = Time.now
          app.save
        end
        # app.add_new_droplet(app.droplet_hash) if app.droplet_hash

        App.find(id: app.id)
      end
    end
  end
end
