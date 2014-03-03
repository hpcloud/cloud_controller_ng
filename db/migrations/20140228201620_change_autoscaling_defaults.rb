Sequel.migration do
  change do
    alter_table :apps do
      set_column_default :min_cpu_threshold, 0
      set_column_default :max_cpu_threshold, 100
      # set_column_default :min_instances, 1  # Not a change.  Just here for documentation.
      set_column_default :max_instances, 2 # Has to be something to make a/s work
    end
  end
end