class UsersController < ApplicationController
  skip_before_action :authenticate_user!, only: [:dashboard]
  before_action :authenticate_via_token_or_devise, only: [:dashboard]

  def dashboard
    # Fetch the user's reflections
    @reflections = current_user.reflections.order(created_at: :desc)
    
    # Highlight specific reflection if reflection_id param present
    if params[:reflection_id].present?
      @highlighted_reflection = @reflections.find_by(id: params[:reflection_id])
    end
  end

  private

  def authenticate_via_token_or_devise
    # If token present, try token authentication
    if params[:token].present?
      user = User.find_by(login_token: params[:token])
      if user
        sign_in(user, bypass: true)
        user.update!(login_token: nil)  # Clear token after use
        # Redirect to clean URL without token
        redirect_to dashboard_path(reflection_id: params[:reflection_id]) and return
      else
        redirect_to root_path, alert: "Invalid login link." and return
      end
    end
    
    # Otherwise require normal Devise authentication
    authenticate_user!
  end
end