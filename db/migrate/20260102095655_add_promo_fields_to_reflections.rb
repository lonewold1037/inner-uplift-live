class AddPromoFieldsToReflections < ActiveRecord::Migration[7.2]
  def change
    add_column :reflections, :free_unlock, :boolean
    add_column :reflections, :promo_code, :string
  end
end
