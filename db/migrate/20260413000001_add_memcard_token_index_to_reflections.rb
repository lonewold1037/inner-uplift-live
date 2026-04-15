class AddMemcardTokenIndexToReflections < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :reflections, :memcard_token, unique: true, algorithm: :concurrently
  end
end
