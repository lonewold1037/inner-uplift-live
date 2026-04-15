class AddMemcardFieldsToReflections < ActiveRecord::Migration[7.2]
  def change
    add_column :reflections, :memcard_token, :string
    add_column :reflections, :memcard_enabled, :boolean, default: false, null: false
    add_column :reflections, :memcard_view_count, :integer, default: 0, null: false
    add_column :reflections, :memcard_enabled_at, :datetime
  end
end
