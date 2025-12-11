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
      output_format: "mp3_44100_128"
    }.to_json

    response = http.request(request)  # ✅ Uses your configured http object
    response.is_a?(Net::HTTPSuccess) ? response.body : nil
  end

  def mix_with_looping_soundscape(voice_path, soundscape, reflection)
    soundscape_temp = Tempfile.new(["soundscape_", ".mp3"], binmode: true)
    soundscape_temp.write(soundscape.audio_file.download)
    soundscape_temp.flush

    mixed_file = Tempfile.new(["extended_mixed_", ".mp3"], binmode: true)

    # Get mix balance settings
    mix = get_mix_balance(reflection.eq_preset)

    # Enhanced filter: EQ, compression, subtle reverb + fade MUSIC ONLY
    command = [
      "ffmpeg", "-y",
      "-i", voice_path,
      "-stream_loop", "-1", "-i", soundscape_temp.path,
      "-filter_complex",
      "[1:a]volume=#{mix[:music]},equalizer=f=2000:width_type=h:width=2000:g=-3,afade=t=out:st=290:d=10[bg];" +
      "[0:a]volume=#{mix[:voice]}," +
      "highpass=f=80," +
      "equalizer=f=1000:width_type=h:width=500:g=2,acompressor=threshold=-16dB:ratio=2.5:attack=30:release=250," +
      "acompressor=threshold=-18dB:ratio=3:attack=20:release=200," +
      "aecho=0.8:0.88:60:0.1[v];" +
      "[bg][v]amix=inputs=2:duration=longest:dropout_transition=2[mixed];[mixed]loudnorm=I=-16:LRA=11:TP=-1.5",
      "-t", "300",
      "-c:a", "libmp3lame", "-q:a", "2",
      mixed_file.path
    ]

    Rails.logger.info "▶️ Running FFmpeg (5-min mix with enriched blend): #{command.join(' ')}"

    _stdout, stderr, status = Open3.capture3(*command)

    unless status.success?
      Rails.logger.error "❌ FFmpeg failed: #{stderr}"
      return nil
    end

    mixed_file
  ensure
    soundscape_temp&.close
    soundscape_temp&.unlink
  end

  def handle_failure(reflection, message)
    Rails.logger.error "❌ ProcessExtendedAudioJob: #{message} for Reflection ##{reflection.id}"
    reflection.update!(status: 'failed')
  end

  def add_poetic_pauses(text)
    return "" unless text.present?

    text
      # turn normal clause endings into gentle pauses
      .gsub(/([a-z])([,;:])\s/i, '\1...\2 ')
      # soften sentence breaks a bit
      .gsub(/([^.])\.\s+([A-Z])/, '\1... \2')
      # slight hesitation before connectors
      .gsub(/\b(but|and|so|yet)\b/i, '...\1')
      # clean up accidental triple dots
      .gsub(/\.{4,}/, '...')
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
      { voice: 1.8, music: 0.12 }
    end
  end
end