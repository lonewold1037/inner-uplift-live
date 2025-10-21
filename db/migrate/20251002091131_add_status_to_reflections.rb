# db/migrate/20251002091131_add_status_to_reflections.rb
class AddStatusToReflections < ActiveRecord::Migration[7.0]
  def change
    add_column :reflections, :status, :string, default: "pending", null: false
  end
end