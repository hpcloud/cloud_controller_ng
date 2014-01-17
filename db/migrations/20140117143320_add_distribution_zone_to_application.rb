Sequel.migration do
  change do
    alter_table :apps do
      add_column :distribution_zone, String, :default => nil
    end
  end
end