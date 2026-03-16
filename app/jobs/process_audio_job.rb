# app/jobs/process_audio_job.rb
require 'net/http'
require 'uri'
require 'net/http/post/multipart'
require 'open3'
require 'fileutils'

class ProcessAudioJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 3

  MAX_WAIT_SECONDS = 60

  def perform(reflection)
    begin
      reflection.update!(status: 'processing_voice')
      Rails.logger.info "--- Starting ProcessAudioJob for reflection ID: #{reflection.id} ---"

      raise "Voice recording is not attached." unless reflection.voice_recording.attached?

      new_voice_id = create_voice_clone(reflection, reflection.voice_recording)
      raise "Failed to create ElevenLabs voice clone." unless new_voice_id

      unless wait_for_voice_ready(new_voice_id)
        delete_voice_clone(new_voice_id)
        raise "Voice clone #{new_voice_id} was not ready in time."
      end

      reflection.update!(eleven_labs_voice_id: new_voice_id)
      edit_voice_settings(new_voice_id)

      reflection.update!(status: 'generating_preview')

      audio_data = synthesize_audio(reflection.recap, new_voice_id)
      raise "Failed to synthesize preview audio from recap." unless audio_data.present?

      reflection.preview_audio.attach(
        io: StringIO.new(audio_data),
        filename: "preview.mp3",
        content_type: "audio/mpeg"
      )

      reflection.update!(status: 'ready_to_mix')
      broadcast_status_update(reflection)
      Rails.logger.info "✅ Preview audio attached. Reflection ##{reflection.id} is ready to mix."

    rescue => e
      handle_failure(reflection, e.message)
    end
  end

  private

  def handle_failure(reflection, message)
    Rails.logger.error "❌ ProcessAudioJob failed: #{message} for Reflection ##{reflection.id}"
    reflection.update!(status: 'failed')
    broadcast_status_update(reflection)
  end

  def broadcast_status_update(reflection)
    # ✅ FIX: Get one representative per category instead of all 42 soundscapes
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

  def create_voice_clone(reflection, webm_attachment)
    tmp_mp3 = Rails.root.join("tmp", "#{SecureRandom.hex}.mp3")
    tmp_webm = Rails.root.join("tmp", "#{SecureRandom.hex}.webm")
    
    begin
      # Save the webm
      File.binwrite(tmp_webm, webm_attachment.download)
      
      Rails.logger.info "🎵 Converting WebM directly to MP3 for ElevenLabs..."
      
      # Convert WebM → MP3 directly (preserves original quality!)
      success = system("ffmpeg -y -i #{tmp_webm} -acodec libmp3lame -b:a 192k #{tmp_mp3}", out: File::NULL, err: File::NULL)
      
      unless success
        Rails.logger.error "❌ FFmpeg WebM→MP3 conversion failed!"
        return nil
      end
      
      Rails.logger.info "✅ MP3 conversion successful, uploading to ElevenLabs..."
      
      uri = URI.parse("https://api.elevenlabs.io/v1/voices/add")
      request = Net::HTTP::Post::Multipart.new(uri.path, {
        'name' => "Reflection Voice #{reflection.id}",
        'files' => UploadIO.new(tmp_mp3.to_s, 'audio/mpeg', "sample.mp3")
      })
      request['xi-api-key'] = ENV["ELEVEN_LABS_API_KEY"]
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
      
      if response.is_a?(Net::HTTPSuccess)
        Rails.logger.info "✅ Voice clone created successfully"
        JSON.parse(response.body)['voice_id']
      else
        Rails.logger.error "❌ ElevenLabs API error: #{response.body}"
        nil
      end
    ensure
      FileUtils.rm_f(tmp_mp3) if tmp_mp3
      FileUtils.rm_f(tmp_webm) if tmp_webm
    end
  end

  def wait_for_voice_ready(voice_id)
    start_time = Time.now
    loop do
      return false if Time.now - start_time > MAX_WAIT_SECONDS
      uri = URI.parse("https://api.elevenlabs.io/v1/voices/#{voice_id}")
      request = Net::HTTP::Get.new(uri)
      request['xi-api-key'] = ENV["ELEVEN_LABS_API_KEY"]
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
      return true if response.is_a?(Net::HTTPSuccess)
      sleep 3
    end
  end

  def edit_voice_settings(voice_id)
    uri = URI.parse("https://api.elevenlabs.io/v1/voices/#{voice_id}/settings/edit")
    headers = { "Content-Type" => "application/json", "xi-api-key" => ENV["ELEVEN_LABS_API_KEY"] }
    body = {
      stability: 0.85,
      similarity_boost: 0.95,
      # use_speaker_boost: true,
      speed: 0.92
    }.to_json
    Net::HTTP.post(uri, body, headers)
  end

  def synthesize_audio(script, voice_id)
    return nil unless script.present?
    # poetic_script = add_poetic_pauses(script)
    uri = URI.parse("https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}")
    headers = { "Accept" => "audio/mpeg", "Content-Type" => "application/json", "xi-api-key" => ENV["ELEVEN_LABS_API_KEY"] }
    body = {
      text: script,
      model_id: "eleven_v3",
      output_format: "mp3_44100_128"
    }.to_json
    response = Net::HTTP.post(uri, body, headers)
    response.is_a?(Net::HTTPSuccess) ? response.body : nil
  end

  def delete_voice_clone(voice_id)
    return unless voice_id.present?
    uri = URI.parse("https://api.elevenlabs.io/v1/voices/#{voice_id}")
    request = Net::HTTP::Delete.new(uri)
    request['xi-api-key'] = ENV["ELEVEN_LABS_API_KEY"]
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
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