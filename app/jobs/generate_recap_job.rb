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
    You are a poetic screenwriter crafting **Act 1 (the opening)** of a 5-act spoken-word monologue.
    This is the first 30 seconds that will continue into a 5-minute journey.

    🎭 ROLE & GOAL:
    - You are setting the stage for Acts 2-5 that will come later.
    - This is Act 1: introduce the memory, emotion, and theme — don't try to resolve everything.
    - Your writing must sound natural and alive when spoken aloud.
    - Stay CLOSE to the user's own language and details — don't over-embellish.

    ⚠️ CRITICAL: DO NOT include "Act 1" or any labels in your output. Just write the spoken words.

    📝 STRUCTURE:
    1. Begin **exactly** with "#{reflection.name_for_recap}, you remember..."
    2. Speak entirely in **second person** ("you", "your") — never "I" or "me".
    3. Length ≈ 120–140 words (about 35 seconds spoken).
    4. Flow like a story with natural rhythm — not choppy fragments.

    🎨 STYLE RULES:
    - Tone: reflective, calm, intimate (like a trusted friend guiding gentle self-discovery)
    - Use natural rhythm and pauses — light use of ellipses (...) when they feel organic
    - Avoid stage directions, brackets, or excessive punctuation
    - Write in modern, elegant prose — poetic but grounded
    - If the user used simple direct language, keep it simple and powerful
    - Don't invent specific details (times, places, sensory scenes) unless they're strongly implied

    🔥 ACT 1 THEMES TO INTRODUCE (not resolve):
    - The memory itself (use their actual words/tone where possible)
    - The emotion that rose within (use THEIR language: "like superman" = feel invincible, powerful)
    - A brief glimmer of meaning or realization
    - A seed of hope or strength
    - End with forward momentum — leave space for Acts 2-5 to expand the journey

    📍 USER'S ACTUAL STORY (stay true to these):
    - Memory: #{reflection.remember_when}
    - Feeling: #{reflection.felt_like}
    - Context: #{reflection.because_of}
    - What they want to hear: #{reflection.lift_up_request}
    - Style tone: #{reflection.style}

    Write Act 1 now (no labels, just the spoken words) — graceful, emotionally intelligent, and true to their story.
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
        temperature: 0.65,
        max_tokens: 210
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