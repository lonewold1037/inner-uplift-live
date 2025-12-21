class AddEmailToReflections < ActiveRecord::Migration[7.2]
  def change
    add_column :reflections, :email, :string
  end
end
