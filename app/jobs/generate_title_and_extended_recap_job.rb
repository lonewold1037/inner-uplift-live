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

    Your task: Continue with Acts 2-5 for approximately 850-900 words (about 4 minutes 30 seconds when spoken).

    ⚠️ CRITICAL: DO NOT include act numbers, chapter titles, or section headers like "Act 2 - Exploration" in your output. Just write the flowing spoken words as one continuous monologue.

    🎭 ACTS 2-5 STRUCTURE (for your planning only, don't write these labels):
    - Act 2: Explore the emotional texture and environment more fully
    - Act 3: Connect emotion to insight and reflection
    - Act 4: Reveal the shift, lesson, or clarity
    - Act 5: Offer gentle closure, integration, and hope

    🔥 CONTINUATION RULES:
    - Match Act 1's tone, pacing, and syntax EXACTLY
    - Stay entirely in second person ("you", "your")
    - DO NOT restart, summarize, or reintroduce
    - Pick up where Act 1 left off and expand the journey
    - Keep sensory language grounded in what's believable
    - If the user used simple language, stay simple and powerful
    - Avoid inventing specific details not in the original inputs

    📍 EXPAND DEEPLY ON:
    - What happened next in their journey
    - How the transformation unfolded over time
    - Specific moments of strength, challenge, or growth
    - Where they are NOW and what lies ahead
    - The fulfillment of their hope: "#{reflection.lift_up_request}"

    📍 REMEMBER THE USER'S ACTUAL STORY:
    - Memory: #{reflection.remember_when}
    - Feeling: #{reflection.felt_like}
    - Context: #{reflection.because_of}
    - What they want to hear: #{reflection.lift_up_request}
    - Style tone: #{reflection.style}

    ⚡ CRITICAL ENDING INSTRUCTION:
    - Plan so it concludes naturally around 850-900 words
    - End with a powerful, complete final thought (not mid-sentence)
    - The last sentence should feel like a satisfying conclusion
    - Leave the listener feeling uplifted, understood, and complete

    Continue Acts 2-5 now (no labels, just flowing speech):
    PROMPT

    continuation = call_openai(prompt, max_tokens: 1400)
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
      temperature: 0.75,
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