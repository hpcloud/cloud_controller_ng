Sequel.migration do
  change do
    create_table :app_versions do
      VCAP::Migration.common(self)

      Integer :app_id, :null => false
      String  :version_guid, :null => false

      index :app_id

      foreign_key [:app_id], :apps, :name => :fk_app_versions_app_id
    end
  end
end
