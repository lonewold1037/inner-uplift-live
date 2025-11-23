# app/controllers/downloads_controller.rb
class DownloadsController < ApplicationController
  before_action :authenticate_user!, only: [:extended_audio]
  
  def preview_audio
    reflection = Reflection.find(params[:id])
    
    if reflection.final_audio.attached?
      send_audio_file(reflection.final_audio, "memflection_preview_#{reflection.id}.mp3")
    else
      head :not_found
    end
  end
  
  def extended_audio
    reflection = current_user.reflections.find(params[:id])
    
    if reflection.extended_audio.attached?
      send_audio_file(reflection.extended_audio, "#{reflection.title || 'memflection'}_extended.mp3")
    else
      head :not_found
    end
  end
  
  private
  
  def send_audio_file(attachment, filename)
    # Set proper headers for downloadable audio
    send_data attachment.download,
              filename: filename,
              type: 'audio/mpeg',
              disposition: 'inline' # 'inline' allows play + download, 'attachment' forces download
  end
end