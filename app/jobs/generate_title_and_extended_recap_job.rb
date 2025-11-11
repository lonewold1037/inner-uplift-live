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
    You are continuing a spoken-word monologue that has already begun.

    The opening (Act 1) is:
    "#{reflection.recap}"

    Your task: continue this monologue through **Acts 2-5**, lasting about 4.5 minutes (≈ 900-1000 words).

    🎭 ROLE & PURPOSE
    - You are the same poetic screenwriter — calm, intimate, reflective.
    - Extend the emotional journey that began in Act 1, carrying the same rhythm and voice.
    - Your job is to **expand, not retell**. Deepen the moment, broaden the meaning.

    🔥 CONTINUATION STYLE RULES
    - Match Act 1's tone, pacing, and syntax — gentle flow, short natural phrases.
    - Stay entirely in **second person** ("you", "your").
    - Do **not** reintroduce the character or summarize what's already said.
    - Avoid inventing new events or imagery not implied by the user's memory.
    - Each act should feel like an evolution:
        *Act 2 - Exploration*: describe emotional texture and environment more fully.  
        *Act 3 - Reflection*: begin connecting emotion to insight.  
        *Act 4 - Realization*: reveal a shift, lesson, or clarity.  
        *Act 5 - Integration*: offer gentle closure, hope, or affirmation.
    - Keep sensory language grounded in what's believable for the user's memory.
    - End with a natural exhale — peace, understanding, or acceptance — not a hard conclusion.

    🎨 THEMES TO WEAVE THROUGH
    - Memory: #{reflection.remember_when}
    - Feeling: #{reflection.felt_like}
    - Context: #{reflection.because_of}
    - What they want to hear: #{reflection.lift_up_request}
    - Style tone: #{reflection.style}

    Write Acts 2-5 now, in the same emotional voice as Act 1.
    PROMPT

    continuation = call_openai(prompt, max_tokens: 1300)
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