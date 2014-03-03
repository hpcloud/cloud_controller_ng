Sequel.migration do
  change do
    alter_table :organizations do
      add_column :is_default, :boolean, :default => false
      add_index :is_default
    end

    alter_table :spaces do
      add_column :is_default, :boolean, :default => false
      add_index :is_default
    end
  end
end