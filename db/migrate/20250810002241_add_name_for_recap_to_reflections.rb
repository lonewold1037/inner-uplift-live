class AddNameForRecapToReflections < ActiveRecord::Migration[7.0]
  def change
    add_column :reflections, :name_for_recap, :string
  end
end
