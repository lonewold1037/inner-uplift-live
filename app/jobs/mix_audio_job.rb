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

      # Get mix balance settings
      mix = get_mix_balance(reflection.eq_preset)

      # Enhanced filter with LOUDNESS NORMALIZATION for maximum volume
      command = [
        "ffmpeg", "-y",
        "-i", voice_temp.path,
        "-i", soundscape_temp.path,
        "-filter_complex",
        "[1:a]volume=#{mix[:music]},equalizer=f=2000:width_type=h:width=2000:g=-3,equalizer=f=100:width_type=h:width=100:g=3[bg];" +
        "[0:a]volume=#{mix[:voice]}," +
        "highpass=f=80," +
        "equalizer=f=3500:width_type=h:width=1500:g=-3," +
        "acompressor=threshold=-20dB:ratio=2:attack=50:release=300[v];" +
        "[bg][v]amix=inputs=2:duration=longest:dropout_transition=2[mixed];[mixed]dynaudnorm=p=0.9:s=5",
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
    soundscapes = Soundscape.where(category: Soundscape::ENABLED_CATEGORIES)
                            .group_by(&:category)
                            .map { |category, soundscapes| soundscapes.first }
    reflection.broadcast_replace_to(
      reflection, 
      target: "reflection_status_area_#{reflection.id}", 
      partial: "reflections/status_content",
      locals: { reflection: reflection, soundscapes: soundscapes }
    )
  end

  def get_mix_balance(preset)
    case preset
    when "voice_prominent"
      { voice: 2.2, music: 0.08 }
    when "music_forward"
      { voice: 1.4, music: 0.20 }
    when "ambient_blend"
      { voice: 1.0, music: 0.25 }
    else # "balanced" or nil
      { voice: 1.8, music: 0.16 }
    end
  end
end
