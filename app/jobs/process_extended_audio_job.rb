# app/jobs/process_extended_audio_job.rb
require 'net/http'
require 'uri'
require 'open3'
require 'tempfile'

class ProcessExtendedAudioJob < ApplicationJob
  queue_as :default
  retry_on Net::ReadTimeout, wait: 10.seconds, attempts: 5  # Specific for timeouts
  retry_on StandardError, wait: 5.seconds, attempts: 3       # Other errors

  def perform(reflection)
    Rails.logger.info "🎬 ProcessExtendedAudioJob: Starting for Reflection ##{reflection.id}"

    unless reflection.eleven_labs_voice_id.present?
      return handle_failure(reflection, "Voice ID is missing - cannot generate extended audio")
    end

    unless reflection.extended_recap.present?
      return handle_failure(reflection, "Extended recap text is missing")
    end

    unless reflection.soundscape&.audio_file&.attached?
      return handle_failure(reflection, "Soundscape is missing")
    end

    begin
      # Step 1: Generate extended TTS using the existing cloned voice
      Rails.logger.info "🗣 Generating extended TTS with voice #{reflection.eleven_labs_voice_id}"
      audio_data = synthesize_extended_audio(reflection.extended_recap, reflection.eleven_labs_voice_id)
      
      unless audio_data.present?
        return handle_failure(reflection, "Failed to synthesize extended audio")
      end

      # Step 2: Save TTS to temp file
      voice_temp = Tempfile.new(["extended_voice_", ".mp3"], binmode: true)
      voice_temp.write(audio_data)
      voice_temp.flush

      # Step 3: Mix with looping soundscape (5 minutes)
      mixed_audio = mix_with_looping_soundscape(voice_temp.path, reflection.soundscape, reflection)

      unless mixed_audio
        return handle_failure(reflection, "Failed to mix extended audio with soundscape")
      end

      # Step 4: Attach as extended_audio
      reflection.extended_audio.attach(
        io: File.open(mixed_audio.path),
        filename: "extended_reflection_#{reflection.id}.mp3",
        content_type: "audio/mpeg"
      )

      reflection.update!(status: 'completed')
      Rails.logger.info "✅ Extended audio complete for Reflection ##{reflection.id}"

      broadcast_dashboard_update(reflection)

      # TODO: Send email notification that extended audio is ready

    rescue => e
      handle_failure(reflection, "Unexpected error: #{e.message}")
    ensure
      voice_temp&.close
      voice_temp&.unlink
      mixed_audio&.close
      mixed_audio&.unlink
    end
  end

  private

  def synthesize_extended_audio(script, voice_id)
    poetic_script = add_poetic_pauses(script)

    uri = URI.parse("https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 180  # 3 minutes (generous for 5-min audio)
    http.open_timeout = 30

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Accept"] = "audio/mpeg"
    request["Content-Type"] = "application/json"
    request["xi-api-key"] = ENV["ELEVEN_LABS_API_KEY"]
    request.body = {
      text: poetic_script,
      model_id: "eleven_multilingual_v2",
      output_format: "mp3_44100_128",
      voice_settings: {
        stability: 0.85,
        similarity_boost: 0.95,
        speed: 0.90,
        use_speaker_boost: true
      }
    }.to_json

    response = http.request(request)  # ✅ Uses your configured http object
    response.is_a?(Net::HTTPSuccess) ? response.body : nil
  end

  def mix_with_looping_soundscape(voice_path, soundscape, reflection)
    soundscape_temp = Tempfile.new(["soundscape_", ".mp3"], binmode: true)
    soundscape_temp.write(soundscape.audio_file.download)
    soundscape_temp.flush

    extended_music = Tempfile.new(["extended_music_", ".mp3"], binmode: true)
    mixed_file = Tempfile.new(["extended_mixed_", ".mp3"], binmode: true)

    # STEP 1: Pre-extend the music to 5 minutes with seamless looping
    # (If track is already 5min, this just adds the fade-out)
    extend_command = [
      "ffmpeg", "-y",
      "-stream_loop", "-1",
      "-i", soundscape_temp.path,
      "-af", "afade=t=out:st=290:d=10",
      "-t", "300",
      "-c:a", "libmp3lame", "-q:a", "2",
      extended_music.path
    ]

    Rails.logger.info "▶️ Pre-extending music to 5 minutes: #{extend_command.join(' ')}"
    
    _stdout_ext, stderr_ext, status_ext = Open3.capture3(*extend_command)

    unless status_ext.success?
      Rails.logger.error "❌ Music extension failed: #{stderr_ext}"
      return nil
    end

    # Get mix balance settings
    mix = get_mix_balance(reflection.eq_preset)

    # STEP 2: Mix voice with pre-extended music (no looping during mix)
    command = [
      "ffmpeg", "-y",
      "-i", voice_path,
      "-i", extended_music.path,
      "-filter_complex",
      "[1:a]volume=#{mix[:music]},equalizer=f=2000:width_type=h:width=2000:g=-3,equalizer=f=100:width_type=h:width=100:g=3[bg];" +
      "[0:a]volume=#{mix[:voice]}," +
      "highpass=f=80," +
      "equalizer=f=3500:width_type=h:width=1500:g=-3," +
      "acompressor=threshold=-20dB:ratio=2:attack=50:release=300[v];" +
      "[bg][v]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0",
      "-t", "300",
      "-c:a", "libmp3lame", "-q:a", "2",
      mixed_file.path
    ]

    Rails.logger.info "▶️ Running FFmpeg (5-min mix with pre-extended music): #{command.join(' ')}"

    _stdout, stderr, status = Open3.capture3(*command)

    unless status.success?
      Rails.logger.error "❌ FFmpeg failed: #{stderr}"
      return nil
    end

    mixed_file
  ensure
    soundscape_temp&.close
    soundscape_temp&.unlink
    extended_music&.close
    extended_music&.unlink
  end

  def handle_failure(reflection, message)
    Rails.logger.error "❌ ProcessExtendedAudioJob: #{message} for Reflection ##{reflection.id}"
    reflection.update!(status: 'failed')
  end

  def add_poetic_pauses(text)
    return "" unless text.present?

    text
      # Add SSML breaks after sentences for natural pacing
      .gsub(/\.\s+/, '.<break time="0.8s"/> ')
      # Shorter pause after commas
      .gsub(/,\s+/, ',<break time="0.3s"/> ')
      # Pause before emotional connectors
      .gsub(/\b(but|and|so|yet|because)\b/i, '<break time="0.2s"/>\1')
      # Paragraph breaks get longer pauses
      .gsub(/\n\n/, '<break time="1.2s"/>')
      .strip
  end

  # ✅ ADD THIS NEW METHOD:
  def broadcast_dashboard_update(reflection)
    # Only broadcast if user exists (safety check)
    return unless reflection.user_id.present?
    
    # Broadcast to the user's dashboard stream
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{reflection.user_id}_dashboard",
      target: "reflection_row_#{reflection.id}",
      partial: "users/reflection_row",
      locals: { reflection: reflection }
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
      { voice: 1.2, music: 0.13 }
    end
  end
end