class AddPurchaseFieldsToReflections < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!
  
  def change
    add_column :reflections, :purchased, :boolean, default: false, null: false
    add_column :reflections, :extended_recap, :text
    add_index :reflections, :purchased, algorithm: :concurrently
  end
end