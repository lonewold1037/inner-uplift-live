# app/jobs/generate_title_and_extended_recap_job.rb
require 'net/http'
require 'uri'
require 'json'

class GenerateTitleAndExtendedRecapJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 3

  def perform(reflection)
    Rails.logger.info "🎬 Starting extended recap generation for Reflection ##{reflection.id}"
    
    # Generate a short, catchy title based on the memory
    title = generate_title(reflection)
    
    # Generate the extended continuation (keeping same style as original)
    extended_script = generate_extended_recap(reflection)
    
    # Save both to the reflection
    reflection.update!(
      title: title,
      extended_recap: extended_script,
      status: 'generating_extended_audio'
    )
    
    # Trigger the extended audio generation
    ProcessExtendedAudioJob.perform_later(reflection)
    
    Rails.logger.info "✅ Title and extended recap generated for Reflection ##{reflection.id}"
  end

  private

  def generate_title(reflection)
    prompt = <<-PROMPT
    Generate a short, poetic 2-4 word title for this memory reflection.
    Make it evocative and meaningful, like "Poker Night" or "Summer's Last Dance".
    
    Memory: #{reflection.remember_when}
    
    Return ONLY the title, nothing else.
    PROMPT

    response = call_openai(prompt, max_tokens: 10)
    response.strip.gsub(/["""]/, '') # Remove quotes if GPT adds them
  end

  def generate_extended_recap(reflection)
    prompt = <<-PROMPT
    You are continuing a 5-act spoken-word monologue that has already begun.

    Act 1 (already recorded) is:
    "#{reflection.recap}"

    THE USER'S NAME IS: #{reflection.name_for_recap}
    USE THIS NAME 3-5 TIMES NATURALLY THROUGHOUT (e.g., "#{reflection.name_for_recap}, you...")

    Your task: Continue with Acts 2-5 for EXACTLY 490-520 words to fill 4:45 of audio.

    ⚠️ CRITICAL RULES:
    - DO NOT invent family members, relationships, pets, or people not mentioned
    - DO NOT add details about jobs, locations, or events not provided
    - DO NOT assume geographical places mentioned are where the person still lives/resides
    - ONLY expand on what the user shared
    - NO act numbers, chapter titles, or section headers

    🔥 CONTINUATION RULES:
     - Write EXACTLY 490-520 words (critical for audio timing)
    - #{style_instructions(reflection.style)}
    - Stay in second person ("you", "your")
    - Use "#{reflection.name_for_recap}" naturally 1 time at the tail end of Act 5
    - Pick up where Act 1 left off

    📍 USER'S ACTUAL STORY (DO NOT ADD TO THIS):
    - Name: #{reflection.name_for_recap}
    - Memory: #{reflection.remember_when}
    - Feeling: #{reflection.felt_like}
    - Context: #{reflection.because_of}
    - Hope: #{reflection.lift_up_request}

    Continue Acts 2-5 now:
    PROMPT

    continuation = call_openai(prompt, max_tokens: 900)  # Reduced to ensure we stay under
    
    words = continuation.split
    if words.count > 550
      Rails.logger.warn "⚠️ GPT generated #{words.count} words, truncating to 600"
      continuation = words.first(550).join(' ')
      # Ensure we end on a complete sentence
      continuation = continuation.sub(/[^.!?]*\z/, '').strip
    end
    
    Rails.logger.info "✅ Continuation: #{words.count} words (after truncation: #{continuation.split.count} words)"
  
    "#{reflection.recap}\n\n#{continuation}"
  end

  def call_openai(prompt, max_tokens:)
    uri = URI.parse("https://api.openai.com/v1/chat/completions")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}"
    }
    
    body = {
      model: "gpt-4-turbo",
      messages: [{ role: "user", content: prompt }],
      temperature: 0.65,
      max_tokens: max_tokens
    }.to_json

    response = http.post(uri.path, body, headers)
    response_body = JSON.parse(response.body)

    if response.is_a?(Net::HTTPSuccess) && response_body.dig("choices", 0, "message", "content")
      response_body["choices"].first["message"]["content"].strip
    else
      error_message = response_body.dig("error", "message") || "Unknown API error"
      raise "OpenAI API Error: #{error_message}"
    end
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