class AddLoginTokenToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :login_token, :string
  end
end
