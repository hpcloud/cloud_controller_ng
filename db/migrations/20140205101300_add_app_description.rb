Sequel.migration do
  change do
    alter_table :apps do
      add_column :description, String, :default => ''
    end
  end
end