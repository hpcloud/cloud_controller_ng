Sequel.migration do
  change do
    alter_table :apps do
      add_column :distribution_zone, String, :default => 'default'
      add_index :distribution_zone
    end
  end
end