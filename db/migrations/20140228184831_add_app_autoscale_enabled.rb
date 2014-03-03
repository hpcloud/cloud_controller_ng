class AddAppAutoscalingEnabled < ActiveRecord::Migration
  change do
    alter_table :apps do
      add_column :autoscaling_enabled, :boolean, :default => false
    end
  end
end
