class UsersController < ApplicationController
  skip_before_action :authenticate_user!, only: [:dashboard]
  before_action :auto_login_from_purchase, only: [:dashboard]

  def dashboard
    if user_signed_in?
      @reflections = current_user.reflections.order(created_at: :desc)
    else
      redirect_to root_path, alert: "Please log in to view your dashboard."
    end
  end

  private

  def auto_login_from_purchase
    return if user_signed_in?
    return unless params[:reflection_id].present?

    reflection = Reflection.find_by(id: params[:reflection_id])
    return unless reflection&.user&.login_token.present?

    # Auto-login the user and consume the token
    sign_in(reflection.user)
    reflection.user.update!(login_token: nil) # One-time use token
    
    Rails.logger.info "✅ Auto-logged in user #{reflection.user.email}"
  end
end