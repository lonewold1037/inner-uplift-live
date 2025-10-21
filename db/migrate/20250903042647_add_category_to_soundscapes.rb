class AddCategoryToSoundscapes < ActiveRecord::Migration[7.0]
  def change
    add_column :soundscapes, :category, :string
  end
end
