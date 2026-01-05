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

    Your task: Continue with Acts 2-5 for EXACTLY 500-520 words (ABSOLUTE MAXIMUM: 620 words).

    🚨 HARD STOP AT 520 WORDS - Audio will cut you off if you exceed this. Count as you write.

    ⚠️ CRITICAL RULES:
    - DO NOT invent family members, relationships, pets, or people not mentioned
    - DO NOT add details about jobs, locations, or events not provided
    - DO NOT assume geographical places mentioned are where the person still lives/resides
    - ONLY expand on what the user shared
    - NO act numbers, chapter titles, or section headers

    🔥 CONTINUATION RULES:
    - Match Act 1's tone exactly
    - Stay in second person ("you", "your")
    - Use "#{reflection.name_for_recap}" naturally 3-5 times
    - Pick up where Act 1 left off

    📍 USER'S ACTUAL STORY (DO NOT ADD TO THIS):
    - Name: #{reflection.name_for_recap}
    - Memory: #{reflection.remember_when}
    - Feeling: #{reflection.felt_like}
    - Context: #{reflection.because_of}
    - Hope: #{reflection.lift_up_request}
    - Style: #{reflection.style}

    Continue Acts 2-5 now (520-540 words max, use #{reflection.name_for_recap} 1-3 times max):
    PROMPT

    continuation = call_openai(prompt, max_tokens: 1000)  # Reduced to ensure we stay under
    
    # HARD TRUNCATION at 600 words (leaves room for recap to total ~740 words = ~4:45 of audio)
    words = continuation.split
    if words.count > 540
      Rails.logger.warn "⚠️ GPT generated #{words.count} words, truncating to 600"
      continuation = words.first(540).join(' ')
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
end