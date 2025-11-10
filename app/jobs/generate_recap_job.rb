# app/jobs/generate_recap_job.rb
require 'net/http'
require 'uri'
require 'json'

class GenerateRecapJob < ApplicationJob
  queue_as :default
  # Retry the job up to 3 times if there are network errors
  retry_on StandardError, wait: 5.seconds, attempts: 3

  def perform(reflection)
    # The reflection's initial status is nil. Let's update it to show we're working.
    reflection.update!(status: 'generating_recap')
    broadcast_status_update(reflection) # Tell the UI we've started

    # Your proven, high-quality prompt
    prompt = <<-PROMPT
    You are a poetic scriptwriter creating a spoken-word monologue for voice performance.

    CRITICAL: Start with exactly this opening line:
    "#{reflection.name_for_recap}, you remember..."

    Your task is to turn the user's reflections into a slow, emotionally rich narrative (≈90 words, ~30 seconds when spoken).

    Focus on **pacing** and **breath** — this script will be spoken aloud.

    Style rules:
    - Use *very short* sentences and fragments.
    - Use ellipses (...) generously to create natural pauses, breaths, and emotional hesitations.
    - Do NOT use em dashes, semicolons, or commas to control rhythm — ellipses should carry the flow.
    - Break often into new lines or paragraphs. Treat each shift of feeling as a new verse.
    - Avoid any bracketed stage notes like [pause] or [breath].
    - Write in second person (“you,” “your”) addressing the listener directly.
    - Aim for a tone that feels reflective, cinematic, and intimate — as if spoken gently, slowly, with feeling.

    The goal: a script that sounds *alive* when read aloud by an expressive voice model.

    User's thoughts:
    Chosen Style: #{reflection.style}
    The name to use: #{reflection.name_for_recap}
    I remember: #{reflection.remember_when}
    It made me feel: #{reflection.felt_like}
    But because: #{reflection.because_of}
    I want to hear: #{reflection.lift_up_request}
    PROMPT

    begin
      uri = URI.parse("https://api.openai.com/v1/chat/completions")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30 # Give the API up to 30 seconds to respond

      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}"
      }
      body = {
        model: "gpt-4-turbo",
        messages: [{ role: "user", content: prompt }],
        temperature: 0.75,
        max_tokens: 120
      }.to_json

      response = http.post(uri.path, body, headers)
      response_body = JSON.parse(response.body)

      if response.is_a?(Net::HTTPSuccess) && response_body.dig("choices", 0, "message", "content")
        recap_text = response_body["choices"].first["message"]["content"].strip
        # ✅ SUCCESS: Update with recap and set status to 'pending' for confirmation
        reflection.update!(recap: recap_text, status: 'pending')
      else
        error_message = response_body.dig("error", "message") || "Unknown API error"
        raise "OpenAI API Error: #{error_message}"
      end

    rescue => e
      Rails.logger.error("Error in GenerateRecapJob for Reflection ##{reflection.id}: #{e.message}")
      # ❌ FAILURE: Update with error and set status to 'failed'
      reflection.update!(recap: "We had trouble generating a recap. Please try again.", status: 'failed')
    end

    # Finally, broadcast the final state (either 'pending' or 'failed') to the UI
    broadcast_status_update(reflection)
  end

  private

  # app/jobs/generate_recap_job.rb

# ... (the perform method and your AI prompt are all perfect) ...

private

# ✅ THE FIX: This method is now simpler and more focused.
  def broadcast_status_update(reflection)
    reflection.broadcast_replace_to(
      reflection,
      target: "reflection_status_area_#{reflection.id}",
      partial: "reflections/status_content",
      locals: { reflection: reflection, soundscapes: Soundscape.all }
    )
  end  
end