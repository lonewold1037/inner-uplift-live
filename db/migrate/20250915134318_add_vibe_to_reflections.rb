class AddVibeToReflections < ActiveRecord::Migration[7.0]
  def change
    add_column :reflections, :vibe, :string
  end
end
