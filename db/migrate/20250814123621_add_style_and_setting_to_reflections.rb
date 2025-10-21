class AddStyleAndSettingToReflections < ActiveRecord::Migration[7.0]
  def change
    add_column :reflections, :style, :string
    add_column :reflections, :setting, :string
  end
end
