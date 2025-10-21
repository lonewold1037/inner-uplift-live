class AddRecapToReflections < ActiveRecord::Migration[7.0]
  def change
    add_column :reflections, :recap, :text
  end
end
