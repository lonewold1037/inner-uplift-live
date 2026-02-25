class AddGiftModeToReflections < ActiveRecord::Migration[7.2]
  def change
    add_column :reflections, :mode, :string, default: "self"
    add_column :reflections, :recipient_name, :string
  end
end