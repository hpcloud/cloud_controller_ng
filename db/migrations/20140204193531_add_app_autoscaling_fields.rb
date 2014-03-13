Sequel.migration do
  # Fields needed for autoscaling based on CPU usage
  up do
    alter_table :apps do
      add_column :min_cpu_threshold, Integer, :default => 20, :null => true
      add_column :max_cpu_threshold, Integer, :default => 80, :null => true
      add_column :min_instances,     Integer, :default => 1,  :null => true
      add_column :max_instances,     Integer, :default => 2,  :null => true
    end
  end
  down do
    alter_table :apps do
      drop_column :min_cpu_threshold
      drop_column :max_cpu_threshold
      drop_column :min_instances
      drop_column :max_instances
    end
  end
end

