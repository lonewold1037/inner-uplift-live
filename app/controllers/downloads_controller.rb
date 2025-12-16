# app/controllers/downloads_controller.rb
class DownloadsController < ApplicationController
  before_action :authenticate_user!, only: [:extended_audio]
  
  def preview_audio
    reflection = Reflection.find(params[:id])
    
    if reflection.final_audio.attached?
      redirect_to reflection.final_audio.url(disposition: :inline), allow_other_host: true
    else
      head :not_found
    end
  end
  
  def extended_audio
    reflection = current_user.reflections.find(params[:id])
    
    if reflection.extended_audio.attached?
      # For playing in modal - redirect to S3 with inline disposition
      if params[:play]
        redirect_to reflection.extended_audio.url(disposition: :inline), allow_other_host: true
      # For downloading - use attachment disposition with nice filename
      else
        redirect_to reflection.extended_audio.url(disposition: :attachment, filename: "#{reflection.title || 'memflection'}_extended.mp3"), allow_other_host: true
      end
    else
      head :not_found
    end
  end
end