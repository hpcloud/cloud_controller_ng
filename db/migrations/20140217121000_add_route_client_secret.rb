Sequel.migration do
  change do
    alter_table :routes do
      add_column :client_secret, String, :default => ''
    end
  end
end
