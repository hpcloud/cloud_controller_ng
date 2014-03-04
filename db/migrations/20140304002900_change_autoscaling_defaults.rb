Sequel.migration do
  change do
    alter_table :apps do
      set_column_default :min_cpu_threshold, 20
      set_column_default :max_cpu_threshold, 80
    end
  end
end
