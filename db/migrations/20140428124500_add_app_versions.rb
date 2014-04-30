Sequel.migration do
  change do
    create_table :app_versions do
      VCAP::Migration.common(self)

      Integer  :app_id, :null => false
      String   :version_guid, :null => false
      Integer  :version_count, :null => false
      Integer  :droplet_id, :null => false
      String   :description, :default => ""

      Integer  :instances, :default => 0
      Integer  :memory, :default => 256

      index :app_id
      index :droplet_id

      foreign_key [:app_id], :apps, :name => :fk_app_versions_app_id
      foreign_key [:droplet_id], :droplets, :name => :fk_app_versions_droplet_id
    end
  end
end
