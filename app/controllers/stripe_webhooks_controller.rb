class StripeWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  def create
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    
    begin
      event = Stripe::Webhook.construct_event(
        payload, sig_header, ENV['STRIPE_WEBHOOK_SECRET']
      )
    rescue JSON::ParserError, Stripe::SignatureVerificationError => e
      Rails.logger.error "⚠️ Webhook signature verification failed: #{e.message}"
      return head :bad_request
    end

    # Handle the checkout.session.completed event
    if event['type'] == 'checkout.session.completed'
      session = event['data']['object']
      handle_successful_payment(session)
    end

    head :ok
  end

  private

  def handle_successful_payment(session)
    reflection_id = session['metadata']['reflection_id']
    customer_email = session['customer_details']['email']
    
    Rails.logger.info "💳 Payment received for Reflection ##{reflection_id}, Email: #{customer_email}"
    
    reflection = Reflection.find(reflection_id)
    
    # Find or create user with login token
    user = User.find_or_create_by(email: customer_email) do |u|
      u.password = SecureRandom.hex(16)
      u.login_token = SecureRandom.urlsafe_base64(32)
    end
    
    # If user already exists but has no token, generate one
    if user.login_token.blank?
      user.update!(login_token: SecureRandom.urlsafe_base64(32))
    end
    
    # Link reflection to user and mark as purchased
    reflection.update!(
      user: user,
      purchased: true
    )
    
    # Update checkout session metadata with login token for success URL
    # Note: We can't update the session after creation, so we'll pass it via our own redirect
    
    # Generate GPT title and trigger extended recap job
    GenerateTitleAndExtendedRecapJob.perform_later(reflection)
    
    Rails.logger.info "✅ User created with token: #{user.login_token}. Extended recap job queued."
  end
end