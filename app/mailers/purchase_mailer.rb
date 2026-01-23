class PurchaseMailer < ApplicationMailer
  default from: "ryan@memflect.com"

  def purchase_confirmation(reflection)
    @reflection = reflection
    @user = reflection.user
    
    # UPDATED: No more tokens. Just point to the dashboard.
    # If they aren't logged in, the app will redirect them to the Magic Link page.
    @dashboard_url = "https://memflect.com/dashboard"
    
    mail(
      to: reflection.email,
      subject: "Your Memflection is being created! ✨",
      reply_to: "ryan@memflect.com"
    )
  end
end