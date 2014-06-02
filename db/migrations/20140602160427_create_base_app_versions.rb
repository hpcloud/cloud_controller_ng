Sequel.migration do
  up do
    self[:apps].each do |app|
      app_id = app[:id]
      if self[:app_versions].where(:app_id => app_id).count > 0
        next
      end
      droplet_id = self[:droplets].where(:app_id => app_id,
                                         :droplet_hash => app[:droplet_hash]).
                                   select(:id)
      if droplet_id
        version_guid = SecureRandom.uuid
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
        from(:apps).where(:id => app_id).update(:version => version_guid)
      end
    end
  end
end
