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
    
    # Try token-based login first
    if params[:token].present?
      user = User.find_by(login_token: params[:token])
      if user
        sign_in(user)
        Rails.logger.info "✅ Auto-logged in user #{user.email} via token"
        return
      end
    end
    
    # Fallback to reflection_id based login
    if params[:reflection_id].present?
      reflection = Reflection.find_by(id: params[:reflection_id])
      if reflection&.user && !reflection.user.login_token.nil?
        sign_in(reflection.user)
        Rails.logger.info "✅ Auto-logged in user #{reflection.user.email} via reflection"
      end
    end
  end
end