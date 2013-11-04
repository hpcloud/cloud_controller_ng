Sequel.migration do
  change do
    alter_table :quota_definitions do
      add_column :allow_sudo, TrueClass, :default => false
    end
  end
end
