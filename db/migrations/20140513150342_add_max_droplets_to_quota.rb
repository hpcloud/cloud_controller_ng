Sequel.migration do
  change do
    alter_table :quota_definitions do
      add_column :total_droplets, Integer, :default => 0
    end
  end
end

