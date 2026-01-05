class PurchaseMailer < ApplicationMailer
  default from: "ryan@memflect.com"

  def purchase_confirmation(reflection)
    @reflection = reflection
    @user = reflection.user
    @dashboard_url = "https://memflect.com/dashboard?token=#{@user.login_token}"
    
    mail(
      to: reflection.email,
      subject: "Your Memflection is being created! ✨"
    )
  end
end
