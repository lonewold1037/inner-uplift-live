class UsersController < ApplicationController
  # Skip Devise auth if token is present, let dashboard handle it
  before_action :authenticate_user_or_token!, only: [:dashboard]

  def dashboard
    # If token is present, authenticate via token
    if params[:token].present? && !user_signed_in?
      user = User.find_by(login_token: params[:token])
      if user
        sign_in(user, bypass: true)  # bypass passwordless for token-based login
        # Clear the token from URL for security
        return redirect_to dashboard_path
      else
        redirect_to root_path, alert: "Invalid or expired login link."
        return
      end
    end

    # Fetch the user's reflections
    @reflections = current_user.reflections.order(created_at: :desc)
    
    # Highlight specific reflection if reflection_id param present
    if params[:reflection_id].present?
      @highlighted_reflection = @reflections.find_by(id: params[:reflection_id])
    end
  end

  private

  def authenticate_user_or_token!
    return if params[:token].present?  # Let dashboard handle token auth
    authenticate_user!  # Otherwise use normal Devise auth
  end
end