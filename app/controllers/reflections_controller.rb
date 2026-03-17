# app/controllers/reflections_controller.rb
class ReflectionsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:new, :create, :show, :record, :receive_audio, :mix_audio, :remix_audio, :apply_eq_preset, :checkout, :redeem_promo]
  skip_before_action :verify_authenticity_token, only: [:checkout, :redeem_promo]
  before_action :set_reflection, only: [:show, :record, :receive_audio, :mix_audio, :remix_audio, :apply_eq_preset]
  before_action :set_soundscapes, only: [:show]

  def new
    if params[:from].present?
      source = Reflection.find_by(id: params[:from])
      @reflection = Reflection.new(source&.slice(
        :remember_when, :felt_like, :because_of, :lift_up_request,
        :name_for_recap, :style, :vibe, :setting, :mode, :recipient_name
      ))
    else
      @reflection = Reflection.new
    end
  end

  def create
    @reflection = user_signed_in? ? current_user.reflections.build(reflection_params_for_create) : Reflection.new(reflection_params_for_create)

    if @reflection.save
      session[:anonymous_reflection_id] = @reflection.id unless user_signed_in?

      @reflection.update(status: 'generating_recap')

      GenerateRecapJob.perform_later(@reflection)

      redirect_to @reflection
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def record
  end

  def receive_audio
    unless params[:audio].present?
      Rails.logger.error "❌ No audio file received for Reflection ##{@reflection.id}"
      return redirect_to record_reflection_path(@reflection), alert: "No audio file was received."
    end

    Rails.logger.info "📥 Received audio: #{params[:audio].original_filename}, #{params[:audio].content_type}, #{params[:audio].size} bytes"

    @reflection.voice_recording.attach(params[:audio])

    if @reflection.voice_recording.attached? && @reflection.save
      Rails.logger.info "🎤 Voice recording attached. Kicking off ProcessAudioJob for Reflection ##{@reflection.id}"

      @reflection.update!(status: 'processing_audio')

      ProcessAudioJob.perform_later(@reflection)

      redirect_to reflection_path(@reflection)
    else
      Rails.logger.error "❌ Failed to save reflection ##{@reflection.id}: #{@reflection.errors.full_messages}"
      redirect_to record_reflection_path(@reflection), alert: "Could not save the audio recording."
    end
  end

  def mix_audio
    soundscape = Soundscape.find(params.dig(:reflection, :soundscape_id))
    @reflection.update!(soundscape: soundscape, status: 'mixing')

    @reflection.broadcast_replace_to(
      @reflection,
      target: "reflection_status_area_#{@reflection.id}",
      partial: "reflections/status_content",
      locals: { reflection: @reflection, soundscapes: Soundscape.all }
    )

    MixAudioJob.perform_later(@reflection, soundscape.id)

    redirect_to @reflection
  rescue ActiveRecord::RecordNotFound
    redirect_to @reflection, alert: "Soundscape not found"
  end

  def remix_audio
    if params.dig(:reflection, :soundscape_category).present?
      category = params.dig(:reflection, :soundscape_category)
      soundscape = Soundscape.where(category: category).order("RANDOM()").first
    else
      soundscape = Soundscape.find(params.dig(:reflection, :soundscape_id))
    end

    @reflection.update!(soundscape: soundscape, status: 'mixing')

    @reflection.broadcast_replace_to(
      @reflection,
      target: "reflection_status_area_#{@reflection.id}",
      partial: "reflections/status_content",
      locals: { reflection: @reflection, soundscapes: Soundscape.all }
    )

    exclude_id = (soundscape.category == @reflection.soundscape&.category) ? @reflection.soundscape_id : nil
    MixAudioJob.perform_later(@reflection, soundscape.category, exclude_id: exclude_id)

    redirect_to @reflection
  rescue ActiveRecord::RecordNotFound
    redirect_to @reflection, alert: "Soundscape not found"
  end

  def apply_eq_preset
    @reflection.reload
    @reflection.update!(eq_preset: params[:eq_preset], status: 'mixing')

    @reflection.broadcast_replace_to(
      @reflection,
      target: "reflection_status_area_#{@reflection.id}",
      partial: "reflections/status_content",
      locals: { reflection: @reflection, soundscapes: set_soundscapes }
    )

    MixAudioJob.perform_later(@reflection, @reflection.soundscape.id)

    redirect_to @reflection
  end

  def checkout
    @reflection = Reflection.find(params[:id])
    customer_email = params[:customer_email]

    @reflection.update!(email: customer_email) if customer_email.present?

    session = Stripe::Checkout::Session.create(
      payment_method_types: ['card'],
      customer_email: customer_email,
      line_items: [{
        price_data: {
          currency: 'usd',
          product_data: {
            name: 'Extended Memflection (5 minutes)',
            description: 'Full-length personalized audio reflection'
          },
          unit_amount: 399
        },
        quantity: 1
      }],
      mode: 'payment',
      success_url: dashboard_url + "?reflection_id=#{@reflection.id}",
      cancel_url: reflection_url(@reflection),
      metadata: {
        reflection_id: @reflection.id
      }
    )

    redirect_to session.url, allow_other_host: true
  end

  def redeem_promo
    @reflection = Reflection.find(params[:id])
    customer_email = params[:customer_email]
    promo_code = params[:promo_code]&.upcase&.strip

    valid_codes = ENV.fetch("PROMO_CODES", "").split(",").map(&:strip).map(&:upcase)

    unless valid_codes.include?(promo_code)
      return redirect_to @reflection, alert: "Invalid gift code. Please try again."
    end

    @reflection.update!(email: customer_email) if customer_email.present?

    user = User.find_or_create_by(email: customer_email) do |u|
      u.password = SecureRandom.hex(16)
      u.login_token = SecureRandom.urlsafe_base64(32)
    end

    if user.login_token.blank?
      user.update!(login_token: SecureRandom.urlsafe_base64(32))
    end

    @reflection.update!(
      user: user,
      purchased: true,
      free_unlock: true,
      promo_code: promo_code,
      email: customer_email
    )

    PurchaseMailer.purchase_confirmation(@reflection).deliver_later

    GenerateTitleAndExtendedRecapJob.perform_later(@reflection)

    redirect_to dashboard_url(token: user.login_token, reflection_id: @reflection.id)
  end

  private

  def set_reflection
    reflection_id = params[:id]
    @reflection = if user_signed_in?
                    current_user.reflections.find(reflection_id)
                  else
                    reflection = Reflection.find(reflection_id)
                    if reflection.purchased? && reflection.user_id != current_user&.id
                      raise ActiveRecord::RecordNotFound
                    else
                      session[:anonymous_reflection_id] = reflection.id
                      reflection
                    end
                  end
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "That reflection could not be found."
  end

  def set_soundscapes
    @soundscapes = Soundscape.where(category: Soundscape::ENABLED_CATEGORIES)
                             .group_by(&:category)
                             .map { |category, soundscapes| soundscapes.first }
  end

  def reflection_params_for_create
    params.require(:reflection).permit(
      :remember_when, :felt_like, :because_of, :lift_up_request,
      :name_for_recap, :style, :vibe, :setting, :mode, :recipient_name,
      :cover_image
    )
  end
end