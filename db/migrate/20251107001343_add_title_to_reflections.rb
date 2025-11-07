class AddTitleToReflections < ActiveRecord::Migration[7.2]
  def change
    add_column :reflections, :title, :string
  end
end
