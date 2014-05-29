Sequel.migration do
  change do
    alter_table :users do
      add_column :logged_in_at, DateTime
    end
  end
end
