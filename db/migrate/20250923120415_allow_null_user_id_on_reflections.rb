class AllowNullUserIdOnReflections < ActiveRecord::Migration[7.0]
  def change
    change_column_null :reflections, :user_id, true
  end
end