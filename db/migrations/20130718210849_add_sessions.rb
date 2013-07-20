Sequel.migration do
  change do
    create_table :sessions do
      VCAP::Migration.common(self)

      Integer :app_id, :null => false
      String :public_key, :null => false

      index :app_id

      foreign_key [:app_id], :apps, :name => :fk_sessions_app_id
    end
  end
end
