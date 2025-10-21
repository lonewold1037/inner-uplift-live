class UsersController < ApplicationController
  before_action :authenticate_user!

  def dashboard
    @reflections = current_user.reflections.order(created_at: :desc)
  end
end
