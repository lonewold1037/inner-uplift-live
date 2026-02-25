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
    prompt = if reflection.mode == "gift"
      <<-PROMPT
      You are a poetic screenwriter crafting **Act 1 (the opening)** of a 5-act spoken-word monologue.
      This is a heartfelt personal message FROM #{reflection.name_for_recap} TO #{reflection.recipient_name}.

      🎭 ROLE & GOAL:
      - This is a gift — a personal message from one person to another about a shared memory.
      - Write in FIRST PERSON from #{reflection.name_for_recap}'s perspective, addressing #{reflection.recipient_name} directly.
      - Your writing must sound natural and alive when spoken aloud.
      - Stay CLOSE to the user's own language and details — don't over-embellish.

      ⚠️ CRITICAL: DO NOT include "Act 1" or any labels in your output. Just write the spoken words.

      📝 STRUCTURE:
      1. Begin **exactly** with "#{reflection.recipient_name}, it's #{reflection.name_for_recap}..." but only speak both names once in Act 1
      2. Write entirely in **first person** ("I", "me", "my") addressing #{reflection.recipient_name} as "you"
      3. Length ≈ 120–140 words (about 35 seconds spoken).
      4. Flow like a heartfelt letter read aloud — not choppy fragments.

      🎨 STYLE RULES:
      - #{style_instructions(reflection.style)}
      - Use natural rhythm and pauses — light use of ellipses (...) when they feel organic
      - Avoid stage directions, brackets, or excessive punctuation
      - Write in modern, elegant prose — poetic but grounded
      - If the user used simple direct language, keep it simple and powerful
      - 🚫 IMPORTANT: Do NOT introduce any physical or environmental details not stated by the user.

      🔥 ACT 1 THEMES TO INTRODUCE (not resolve):
      - The shared memory (use their actual words/tone where possible)
      - The emotion it stirred in the sender
      - A brief glimmer of why this person matters
      - A seed of what they want the recipient to know
      - End with forward momentum — leave space for Acts 2-5

      📍 THE SENDER'S ACTUAL WORDS (stay true to these):
      - Memory: #{reflection.remember_when}
      - Feeling: #{reflection.felt_like}
      - Context: #{reflection.because_of}
      - What they want #{reflection.recipient_name} to know: #{reflection.lift_up_request}

      Write Act 1 now (no labels, just the spoken words) — graceful, emotionally intelligent, and true to their story.
      PROMPT
    else
      <<-PROMPT
      You are a poetic screenwriter crafting **Act 1 (the opening)** of a 5-act spoken-word monologue.
      This is the first 30 seconds that will continue into a 5-minute journey.

      🎭 ROLE & GOAL:
      - You are setting the stage for Acts 2-5 that will come later.
      - This is Act 1: introduce the memory, emotion, and theme — don't try to resolve everything.
      - Your writing must sound natural and alive when spoken aloud.
      - Stay CLOSE to the user's own language and details — don't over-embellish.

      ⚠️ CRITICAL: DO NOT include "Act 1" or any labels in your output. Just write the spoken words.

      📝 STRUCTURE:
      1. Begin **exactly** with "#{reflection.name_for_recap}, you remember..." but only speak #{reflection.name_for_recap} once in Act 1
      2. Speak entirely in **second person** ("you", "your") — never "I" or "me".
      3. Length ≈ 120–140 words (about 35 seconds spoken).
      4. Flow like a story with natural rhythm — not choppy fragments.

      🎨 STYLE RULES:
      - #{style_instructions(reflection.style)}
      - Use natural rhythm and pauses — light use of ellipses (...) when they feel organic
      - Avoid stage directions, brackets, or excessive punctuation
      - Write in modern, elegant prose — poetic but grounded
      - If the user used simple direct language, keep it simple and powerful
      - 🚫 IMPORTANT: Do NOT introduce any physical or environmental details (location, room, furniture, weather, mist, droplets, light, time of day, or scene imagery). Only use details explicitly stated by the user. If a detail is not provided, keep it neutral and unspecified.

      🔥 ACT 1 THEMES TO INTRODUCE (not resolve):
      - The memory itself (use their actual words/tone where possible)
      - The emotion that rose within (use THEIR language but enrich it with the users chosen #{style_instructions(reflection.style)})
      - A brief glimmer of meaning or realization
      - A seed of hope or strength
      - End with forward momentum — leave space for Acts 2-5 to expand the journey

      📍 USER'S ACTUAL STORY (stay true to these):
      - Memory: #{reflection.remember_when}
      - Feeling: #{reflection.felt_like}
      - Context: #{reflection.because_of}
      - What they want to hear: #{reflection.lift_up_request}

      Write Act 1 now (no labels, just the spoken words) — graceful, emotionally intelligent, and true to their story.
      PROMPT
    end

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

  def broadcast_status_update(reflection)
    reflection.broadcast_replace_to(
      reflection,
      target: "reflection_status_area_#{reflection.id}",
      partial: "reflections/status_content",
      locals: { reflection: reflection, soundscapes: Soundscape.all }
    )
  end

  def style_instructions(style)
    case style&.upcase
    when "REFLECTIVE"
      "Tone: thoughtful and introspective. Like journaling out loud to yourself. Gentle pauses for processing. Contemplative but not heavy. Ask quiet questions. Let realizations dawn slowly."
    when "MOTIVATIONAL"
      "Tone: energizing and empowering. Build momentum throughout. Use strong, active verbs. Make them feel capable and ready to act. Coach energy - firm but believing in them. End with fire."
    when "HEARTFELT"
      "Tone: warm and emotionally rich. Tender without being sappy. Let vulnerability shine through naturally. Like a letter you'd write to yourself on a hard day. Acknowledge the weight, honor the feeling."
    when "HUMOROUS"
      "Tone: witty and warm. Find the funny side without mocking the memory. Self-aware humor, gentle irony. Make them smile or chuckle. Light touch - don't force jokes. Playful observations about life."
    when "PEACEFUL"
      "Tone: serene and grounding. Slow, spacious rhythm. Like a calm lake at dawn. Breathe between thoughts. No rush. Soft landings on each sentence. Meditative, almost hypnotic flow."
    when "EPIC"
      "Tone: cinematic and dramatic. They are the hero of this story. Big sweeping moments. Build to crescendos. Use vivid imagery. Movie trailer energy - make their life feel legendary."
    when "GRATEFUL"
      "Tone: appreciative and warm. Count the blessings hidden in the memory. Notice the small gifts. Gratitude without toxic positivity - acknowledge the real while finding the gold. Gentle celebration."
    else
      "Tone: reflective, calm, intimate"
    end
  end  
end