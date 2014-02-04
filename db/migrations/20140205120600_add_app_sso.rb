Sequel.migration do
  change do
    alter_table :apps do
      add_column :sso_enabled, :boolean, :default => false
    end
  end
end