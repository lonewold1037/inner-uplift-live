class CreateReflections < ActiveRecord::Migration[7.0]
  def change
    create_table :reflections do |t|
      t.text :remember_when
      t.text :felt_like
      t.text :because_of
      t.text :lift_up_request
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
