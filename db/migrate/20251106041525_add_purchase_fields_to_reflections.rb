class AddPurchaseFieldsToReflections < ActiveRecord::Migration[7.2]
  def change
    add_column :reflections, :purchased, :boolean
    add_column :reflections, :extended_recap, :text
    add_index :reflections, :purchased
  end
end
