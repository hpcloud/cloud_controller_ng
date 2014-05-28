Sequel.migration do
  up do
    # ActiveState merge: this table doesn't exist, but db:migrate wants
    # this file, so just comment out the next line.
    # drop_table(:domains_organizations)
  end
end
