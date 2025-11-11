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
    
    The opening (already recorded) is:
    "#{reflection.recap}"
    
    Your task: Continue this exact same style and tone for approximately 880 more tokens (4.5 minutes when spoken).
    
    CRITICAL STYLE MATCHING RULES:
    - Match the existing rhythm, pacing, and emotional tone EXACTLY
    - Continue using the same sentence structure patterns (short fragments, ellipses)
    - Maintain the same perspective (second person "you")
    - Keep the same level of poetic imagery and intimacy
    - DO NOT restart or summarize — pick up seamlessly where it left off
    
    Expand deeply on:
    - Sensory details of the memory
    - Emotional layers and meaning
    - The transformation or lesson within the experience
    
    Original context to reference:
    Style: #{reflection.style}
    Setting: #{reflection.setting}
    Name: #{reflection.name_for_recap}
    Memory: #{reflection.remember_when}
    Feeling: #{reflection.felt_like}
    Because: #{reflection.because_of}
    Uplift request: #{reflection.lift_up_request}
    
    Continue the narrative now:
    PROMPT

    continuation = call_openai(prompt, max_tokens: 1300)
    
    # Combine original recap + continuation for the full extended version
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