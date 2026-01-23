class UsersController < ApplicationController
  # 1. Protect the dashboard. If they aren't logged in, Devise redirects to login page.
  before_action :authenticate_user!, only: [:dashboard]

  def dashboard
    # 2. Fetch the user's reflections
    @reflections = current_user.reflections.order(created_at: :desc)
  end
end