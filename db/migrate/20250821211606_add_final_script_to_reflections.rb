class AddFinalScriptToReflections < ActiveRecord::Migration[7.0]
  def change
    add_column :reflections, :final_script, :text
  end
end
