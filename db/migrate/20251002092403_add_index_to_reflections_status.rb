# db/migrate/YYYYMMDDHHMMSS_add_index_to_reflections_status.rb
class AddIndexToReflectionsStatus < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :reflections, :status, algorithm: :concurrently
  end
end