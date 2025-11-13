# app/jobs/process_extended_audio_job.rb
require 'net/http'
require 'uri'
require 'open3'
require 'tempfile'

class ProcessExtendedAudioJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 3

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
      mixed_audio = mix_with_looping_soundscape(voice_temp.path, reflection.soundscape)

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
    headers = {
      "Accept" => "audio/mpeg",
      "Content-Type" => "application/json",
      "xi-api-key" => ENV["ELEVEN_LABS_API_KEY"]
    }
    body = {
      text: poetic_script,
      model_id: "eleven_multilingual_v2",
      output_format: "mp3_44100_128"
    }.to_json

    response = Net::HTTP.post(uri, body, headers)
    response.is_a?(Net::HTTPSuccess) ? response.body : nil
  end

  def mix_with_looping_soundscape(voice_path, soundscape)
    soundscape_temp = Tempfile.new(["soundscape_", ".mp3"], binmode: true)
    soundscape_temp.write(soundscape.audio_file.download)
    soundscape_temp.flush

    mixed_file = Tempfile.new(["extended_mixed_", ".mp3"], binmode: true)

    # FFmpeg command: Loop soundscape, mix with voice, fade out properly
    command = [
      "ffmpeg", "-y",
      "-i", voice_path,
      "-stream_loop", "-1", "-i", soundscape_temp.path,
      "-filter_complex",
      "[1:a]volume=0.15,afade=t=out:st=290:d=10[bg];[0:a]volume=1.5[v];[bg][v]amix=inputs=2:duration=longest:dropout_transition=0",
      "-t", "300",  # 5 minutes = 300 seconds
      "-c:a", "libmp3lame", "-q:a", "2",
      mixed_file.path
    ]

    Rails.logger.info "▶️ Running FFmpeg (5-min mix with fade): #{command.join(' ')}"

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
end