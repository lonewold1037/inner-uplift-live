require 'open3'
require 'tempfile'

class MixAudioJob < ApplicationJob
  queue_as :default

  def perform(reflection, soundscape_id_or_category, exclude_id: nil)
    Rails.logger.info "🎛 MixAudioJob: Starting work on Reflection ##{reflection.id}"

    # If it's a number, treat as ID (backward compatibility)
    # Otherwise, treat as category and pick random
    if soundscape_id_or_category.is_a?(Integer) || soundscape_id_or_category.to_s =~ /^\d+$/
      soundscape = Soundscape.find_by(id: soundscape_id_or_category)
    else
      # Pick random soundscape from category, excluding the one they just heard
      query = Soundscape.where(category: soundscape_id_or_category)
      query = query.where.not(id: exclude_id) if exclude_id
      soundscape = query.order("RANDOM()").first

      # Fallback: if exclusion left zero tracks, pick any from category
      if soundscape.nil? && exclude_id
        soundscape = Soundscape.where(category: soundscape_id_or_category).order("RANDOM()").first
      end
    end

    unless reflection.preview_audio.attached?
      return handle_failure(reflection, "Preview audio is missing.")
    end

    unless soundscape&.audio_file&.attached?
      return handle_failure(reflection, "Soundscape not found or missing audio.")
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

      # Get EQ preset filter
      eq_filter = get_voice_eq_filter(reflection.eq_preset)

      # Enhanced filter with LOUDNESS NORMALIZATION for maximum volume
      command = [
        "ffmpeg", "-y",
        "-i", voice_temp.path,
        "-i", soundscape_temp.path,
        "-filter_complex",
        "[1:a]volume=0.12,equalizer=f=2000:width_type=h:width=2000:g=-3[bg];" +
        "[0:a]volume=1.8," +
        "highpass=f=80," +
        "#{eq_filter}," +
        "acompressor=threshold=-18dB:ratio=3:attack=20:release=200," +
        "aecho=0.8:0.88:60:0.1[v];" +
        "[bg][v]amix=inputs=2:duration=longest:dropout_transition=2[mixed];" +
        "[mixed]loudnorm=I=-16:LRA=11:TP=-1.5",
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

  def get_voice_eq_filter(preset)
    case preset
    when "warm_deep"
      "equalizer=f=200:width_type=h:width=100:g=4,equalizer=f=3000:width_type=h:width=1000:g=-2"
    when "ethereal_drift"
      "equalizer=f=100:width_type=h:width=50:g=-3,equalizer=f=8000:width_type=h:width=2000:g=4,aecho=0.9:0.85:40:0.2"
    when "crystal_mind"
      "equalizer=f=4000:width_type=h:width=1500:g=5,equalizer=f=200:width_type=h:width=100:g=-3,highpass=f=100"
    when "whisper_presence"
      "acompressor=threshold=-20dB:ratio=6:attack=10:release=100,equalizer=f=2500:width_type=h:width=1000:g=6"
    when "hypnotic_tunnel"
      "equalizer=f=500:width_type=h:width=200:g=3,aecho=1.0:0.7:80:0.3,aphaser=speed=0.5"
    when "studio_calm"
      "equalizer=f=1000:width_type=h:width=500:g=2,acompressor=threshold=-16dB:ratio=2.5:attack=30:release=250"
    when "dream_soft"
      "volume=1.5,equalizer=f=6000:width_type=h:width=2000:g=3,aecho=0.7:0.9:50:0.15,acompressor=threshold=-22dB:ratio=4:attack=15:release=150"
    else
      "equalizer=f=200:width_type=h:width=100:g=2,equalizer=f=3000:width_type=h:width=1000:g=1"
    end
  end
end
