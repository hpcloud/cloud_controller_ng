Sequel.migration do
  change do
    alter_table :apps do
      add_column :restart_required, :boolean, :default => false
      add_column :restart_required_state_json, String, :default => ''
      add_index :restart_required
    end
  end
end