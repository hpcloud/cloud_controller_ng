# Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
Sequel.migration do
  change do
    alter_table :users do
      add_column :logged_in_at, DateTime
    end
  end
end