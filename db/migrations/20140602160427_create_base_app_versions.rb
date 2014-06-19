Sequel.migration do
  up do
    self[:apps].each do |app|
      app_id = app[:id]
      if self[:app_versions].where(:app_id => app_id).count > 0
        next
      end
      droplets = self[:droplets].where(:app_id => app_id,
                                         :droplet_hash => app[:droplet_hash]).
                                 select(:id).
                                 to_a
      if droplets.size > 0
        droplet_id = droplets.first[:id]
        if droplet_id
          version_guid = app[:version]
          if !version_guid
            version_guid = SecureRandom.uuid
            update_app = true
          else
            update_app = false
          end
          now = Time.now
          self[:app_versions].insert(:guid => SecureRandom.uuid,
                                     :created_at => now,
                                     :app_id => app_id,
                                     :version_guid => version_guid,
                                     :version_count => 1,
                                     :droplet_id => droplet_id,
                                     :description => "upgraded existing application",
                                     :instances => app[:instances],
                                     :memory => app[:memory])
          if update_app
            from(:apps).where(:id => app_id).update(:version => version_guid)
          end
        end
      end
    end
  end
end
