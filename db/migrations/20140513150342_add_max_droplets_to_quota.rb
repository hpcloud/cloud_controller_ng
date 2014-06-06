Sequel.migration do
  change do
    alter_table :quota_definitions do
      add_column :total_droplets, Integer, :default => 5
    end
  end
end

