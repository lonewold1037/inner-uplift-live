# db/migrate/xxxxxxxx_remove_status_default_from_reflections.rb
class RemoveStatusDefaultFromReflections < ActiveRecord::Migration[7.2]
  def change
    # This removes the "default: 'pending'" rule from the status column.
    # We specify 'from' and 'to' so the migration is reversible.
    change_column_default :reflections, :status, from: "pending", to: nil

    # This removes the "null: false" rule, allowing the status to be empty (nil).
    change_column_null :reflections, :status, true
  end
end