# app/jobs/mix_audio_job.rb
require 'open3'
require 'tempfile'

class MixAudioJob < ApplicationJob
  queue_as :default

  def perform(reflection, soundscape_id)
    Rails.logger.info "🎛 MixAudioJob: Starting work on Reflection ##{reflection.id}"

    soundscape = Soundscape.find_by(id: soundscape_id)

    unless reflection.preview_audio.attached?
      return handle_failure(reflection, "Preview audio is missing.")
    end

    unless soundscape&.audio_file&.attached?
      return handle_failure(reflection, "Soundscape ##{soundscape_id} not found or missing audio.")
    end

    voice_temp = nil
    soundscape_temp = nil
    mixed_file = nil

    begin
      voice_temp = Tempfile.new(["voice_", ".mp3"], binmode: true)
      voice_temp.write(reflection.preview_audio.download)
      voice_temp.flush

      soundscape_temp = Tempfile.new(["soundscape_", ".mp3"], binmode: true)
      soundscape_temp.write(soundscape.audio_file.download)
      soundscape_temp.flush

      mixed_file = Tempfile.new(["mixed_", ".mp3"], binmode: true)

      command = [
        "ffmpeg", "-y",
        "-i", voice_temp.path,
        "-i", soundscape_temp.path,
        "-filter_complex", "[0:a]volume=1.5[v];[1:a]volume=0.15[bg];[bg][v]amix=inputs=2:duration=longest",
        "-t", "30", "-c:a", "libmp3lame", "-q:a", "2",
        mixed_file.path
      ]

      Rails.logger.info "▶️ Running FFMPEG: #{command.join(' ')}"
      
      _stdout_str, stderr_str, status = Open3.capture3(*command)

      unless status.success?
        return handle_failure(reflection, "FFMPEG mix failed: #{stderr_str}")
      end

      reflection.final_audio.attach(
        io: File.open(mixed_file.path),
        filename: "reflection_#{reflection.id}_mixed.mp3",
        content_type: "audio/mpeg"
      )
      
      reflection.update!(status: 'completed')
      broadcast_status_update(reflection)
      Rails.logger.info "✅ Final audio attached for Reflection ##{reflection.id}"

    rescue => e
      handle_failure(reflection, "An unexpected error occurred in MixAudioJob: #{e.message}")
    ensure
      voice_temp&.close
      voice_temp&.unlink
      soundscape_temp&.close
      soundscape_temp&.unlink
      mixed_file&.close
      mixed_file&.unlink
    end
  end

  private

  def handle_failure(reflection, message)
    Rails.logger.error "❌ #{message} for Reflection ##{reflection.id}"
    reflection.update!(status: 'failed')
    broadcast_status_update(reflection)
  end

  def broadcast_status_update(reflection)
    reflection.broadcast_replace_to(
      reflection, 
      target: "reflection_status_area_#{reflection.id}", 
      partial: "reflections/status_content",
      locals: { reflection: reflection, soundscapes: Soundscape.all }
    )
  end
end