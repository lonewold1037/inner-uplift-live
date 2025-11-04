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
    wav_file_path = nil
    begin
      reflection.update!(status: 'processing_voice')
      Rails.logger.info "--- Starting ProcessAudioJob for reflection ID: #{reflection.id} ---"

      raise "Voice recording is not attached." unless reflection.voice_recording.attached?

      wav_file_path = convert_to_wav(reflection.voice_recording)
      raise "Could not convert voice recording to WAV." unless wav_file_path

      new_voice_id = create_voice_clone(reflection, wav_file_path)
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
    ensure
      FileUtils.rm_f(wav_file_path) if wav_file_path
    end
  end

  private

  def handle_failure(reflection, message)
    Rails.logger.error "❌ ProcessAudioJob failed: #{message} for Reflection ##{reflection.id}"
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

  def convert_to_wav(attachment)
    tmp_webm = Rails.root.join("tmp", "#{SecureRandom.hex}.webm")
    tmp_wav  = Rails.root.join("tmp", "#{SecureRandom.hex}.wav")
    begin
      File.binwrite(tmp_webm, attachment.download)
      success = system("ffmpeg -y -i #{tmp_webm} -ar 44100 -ac 1 -c:a pcm_s16le #{tmp_wav}", out: File::NULL, err: File::NULL)
      return tmp_wav.to_s if success
      nil
    ensure
      FileUtils.rm_f(tmp_webm)
    end
  end

  def create_voice_clone(reflection, wav_file_path)
    tmp_mp3 = Rails.root.join("tmp", "#{SecureRandom.hex}.mp3")
  
    begin
      Rails.logger.info "🎵 Converting WAV to MP3 for ElevenLabs..."
      
      # Convert WAV to MP3 for ElevenLabs
      success = system("ffmpeg -y -i #{wav_file_path} -acodec libmp3lame -q:a 2 #{tmp_mp3}", out: File::NULL, err: File::NULL)
      
      unless success
        Rails.logger.error "❌ FFmpeg WAV->MP3 conversion failed!"
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
    body = { stability: 0.35, similarity_boost: 0.95 }.to_json
    Net::HTTP.post(uri, body, headers)
  end

  def synthesize_audio(script, voice_id)
    return nil unless script.present?
    uri = URI.parse("https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}")
    headers = { "Accept" => "audio/mpeg", "Content-Type" => "application/json", "xi-api-key" => ENV["ELEVEN_LABS_API_KEY"] }
    body = { text: script, model_id: "eleven_multilingual_v2", voice_settings: { speed: 0.90 } }.to_json
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
end