class AddEqPresetToReflections < ActiveRecord::Migration[7.2]
  def change
    add_column :reflections, :eq_preset, :string
  end
end
