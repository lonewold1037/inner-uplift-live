class MemcardsController < ApplicationController
  layout "memcard"

  # This is a PUBLIC portal — no authentication required.
  
  # Anyone with a valid token can view the Memcard.
  skip_before_action :authenticate_user!, only: [:show]

  # Disable Devise's auto-redirect-to-login for this controller
  # (in case any before_action inheritance tries to block unauthenticated users)
  before_action :ensure_memcard_exists, only: [:show]

  def show
    @reflection = @memcard_reflection

    # Increment view counter atomically (avoids race conditions if multiple
    # viewers hit the page simultaneously)
    Reflection.where(id: @reflection.id).update_all("memcard_view_count = memcard_view_count + 1")

    # Reload so the view shows the fresh count
    @reflection.reload
  end

  private

  def ensure_memcard_exists
    @memcard_reflection = Reflection.with_active_memcard.find_by(memcard_token: params[:token])

    unless @memcard_reflection
      # Token invalid, disabled, or reflection deleted — show the "no longer available" page
      render "memcards/disabled", status: :not_found and return
    end

    # Extra safety: only show Memcards for reflections with extended_audio attached
    # (purchased reflections that have finished processing)
    unless @memcard_reflection.extended_audio.attached?
      render "memcards/disabled", status: :not_found and return
    end
  end
end
