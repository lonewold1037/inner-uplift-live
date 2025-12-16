# app/controllers/downloads_controller.rb
class DownloadsController < ApplicationController
  before_action :authenticate_user!, only: [:extended_audio]
  
  def preview_audio
    reflection = Reflection.find(params[:id])
    
    if reflection.final_audio.attached?
      # Clean S3 URL - no Rails parameters
      blob = reflection.final_audio.blob
      url = "https://#{ENV['AWS_BUCKET']}.s3.#{ENV['AWS_REGION']}.amazonaws.com/#{blob.key}"
      redirect_to url, allow_other_host: true
    else
      head :not_found
    end
  end
  
  def extended_audio
    reflection = current_user.reflections.find(params[:id])
    
    if reflection.extended_audio.attached?
      blob = reflection.extended_audio.blob
      
      if params[:play]
        # For playing - clean S3 URL with no disposition parameters
        url = "https://#{ENV['AWS_BUCKET']}.s3.#{ENV['AWS_REGION']}.amazonaws.com/#{blob.key}"
      else
        # For downloading - use Rails URL with attachment
        url = reflection.extended_audio.url(disposition: :attachment, filename: "#{reflection.title || 'memflection'}_extended.mp3")
      end
      
      redirect_to url, allow_other_host: true
    else
      head :not_found
    end
  end
end