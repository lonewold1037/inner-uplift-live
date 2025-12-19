# app/controllers/reflections_controller.rb
class ReflectionsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:new, :create, :show, :record, :receive_audio, :mix_audio, :remix_audio, :apply_eq_preset, :checkout]
  skip_before_action :verify_authenticity_token, only: [:checkout]
  before_action :set_reflection, only: [:show, :record, :receive_audio, :mix_audio, :remix_audio, :apply_eq_preset]
  before_action :set_soundscapes, only: [:show]

  def new
    @reflection = Reflection.new
  end

  def create
    @reflection = user_signed_in? ? current_user.reflections.build(reflection_params_for_create) : Reflection.new(reflection_params_for_create)

    if @reflection.save
      session[:anonymous_reflection_id] = @reflection.id unless user_signed_in?

      # ✅ THE FIX: Set the initial status here, before the redirect.
      # This guarantees the user sees the loading screen immediately.
      @reflection.update(status: 'generating_recap')
      
      # ✅ IMPROVEMENT: Instead of waiting for the API, start a job and redirect immediately.
      GenerateRecapJob.perform_later(@reflection)
      
      # The user is sent to the 'show' page right away. The recap will appear when the job is done.
      redirect_to @reflection
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    # The before_actions handle finding @reflection and @soundscapes.
  end

  def record
    # Renders the recording page.
  end

  def receive_audio
    unless params[:audio].present?
      return redirect_to record_reflection_path(@reflection), alert: "No audio file was received."
    end

    @reflection.voice_recording.attach(params[:audio])

    if @reflection.save
      Rails.logger.info "🎤 Voice recording attached. Kicking off ProcessAudioJob for Reflection ##{@reflection.id}"
      
      # Set status immediately so user sees "Processing..." on the show page
      @reflection.update!(status: 'processing_audio')

      ProcessAudioJob.perform_later(@reflection)

      redirect_to reflection_path(@reflection)
    else
      redirect_to record_reflection_path(@reflection), alert: "Could not save the audio recording."
    end
  end

  def mix_audio
    soundscape = Soundscape.find(params.dig(:reflection, :soundscape_id))
    @reflection.update!(soundscape: soundscape, status: 'mixing')
    
    # Immediately broadcast the mixing status
    @reflection.broadcast_replace_to(
      @reflection,
      target: "reflection_status_area_#{@reflection.id}",
      partial: "reflections/status_content",
      locals: { reflection: @reflection, soundscapes: Soundscape.all }
    )
    
    # Queue the job
    MixAudioJob.perform_later(@reflection, soundscape.id)
    
    # Redirect to show page - same pattern as create and receive_audio
    redirect_to @reflection
  rescue ActiveRecord::RecordNotFound
    redirect_to @reflection, alert: "Soundscape not found"
  end

  def remix_audio
    # Handle both category (from dropdown) and soundscape_id (from shuffle button)
    if params.dig(:reflection, :soundscape_category).present?
      category = params.dig(:reflection, :soundscape_category)
      soundscape = Soundscape.where(category: category).order("RANDOM()").first
    else
      soundscape = Soundscape.find(params.dig(:reflection, :soundscape_id))
    end

    @reflection.update!(soundscape: soundscape, status: 'mixing')

    # Broadcast mixing status
    @reflection.broadcast_replace_to(
      @reflection,
      target: "reflection_status_area_#{@reflection.id}",
      partial: "reflections/status_content",
      locals: { reflection: @reflection, soundscapes: Soundscape.all }
    )

    # Only exclude current track if staying in same category (shuffle), not when switching categories
    exclude_id = (soundscape.category == @reflection.soundscape&.category) ? @reflection.soundscape_id : nil
    MixAudioJob.perform_later(@reflection, soundscape.category, exclude_id: exclude_id)
    
    redirect_to @reflection
  rescue ActiveRecord::RecordNotFound
    redirect_to @reflection, alert: "Soundscape not found"
  end

  def apply_eq_preset
    @reflection.reload  # ✅ Refresh from database to get latest soundscape
    @reflection.update!(eq_preset: params[:eq_preset], status: 'mixing')
    
    @reflection.broadcast_replace_to(
      @reflection,
      target: "reflection_status_area_#{@reflection.id}",
      partial: "reflections/status_content",
      locals: { reflection: @reflection, soundscapes: set_soundscapes }
    )
    
    # Pass the ID so it uses the exact current track
    MixAudioJob.perform_later(@reflection, @reflection.soundscape.id)
    
    redirect_to @reflection
  end
  
  def checkout
    @reflection = Reflection.find(params[:id])
    
    session = Stripe::Checkout::Session.create(
      payment_method_types: ['card'],
      line_items: [{
        price_data: {
          currency: 'usd',
          product_data: {
            name: 'Extended Memflection (5 minutes)',
            description: 'Full-length personalized audio reflection'
          },
          unit_amount: 199 # $1.99 in cents
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

  private

  def set_reflection
    reflection_id = params[:id]
    @reflection = if user_signed_in?
                    current_user.reflections.find(reflection_id)
                  else
                    # For guests: allow access to unpurchased reflections even if session is lost
                    reflection = Reflection.find(reflection_id)
                    # Only block access to purchased reflections (those require ownership)
                    if reflection.purchased? && reflection.user_id != current_user&.id
                      raise ActiveRecord::RecordNotFound
                    else
                      # Store in session for continuity
                      session[:anonymous_reflection_id] = reflection.id
                      reflection
                    end
                  end
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "That reflection could not be found."
  end

  def set_soundscapes
    # Get one representative soundscape per category for the dropdown
    @soundscapes = Soundscape.all.group_by(&:category).map { |category, soundscapes| soundscapes.first }
  end

  def reflection_params_for_create
    params.require(:reflection).permit(:remember_when, :felt_like, :because_of, :lift_up_request, :name_for_recap, :style, :vibe, :setting)
  end
end