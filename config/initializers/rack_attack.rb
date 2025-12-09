class Rack::Attack
  # Allow all requests from localhost during development
  safelist('allow-localhost') do |req|
    req.ip == '127.0.0.1' || req.ip == '::1'
  end

  # Throttle reflection creation to 3 per day per IP
  throttle('reflections/ip', limit: 3, period: 24.hours) do |req|
    if req.path == '/reflections' && req.post?
      req.ip
    end
  end

  # Throttle Stripe checkout to prevent spam
  throttle('stripe_checkout/ip', limit: 10, period: 1.hour) do |req|
    if req.path.match?(/reflections\/\d+\/checkout/) && req.post?
      req.ip
    end
  end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |env|
    retry_after = env['rack.attack.match_data'][:period]
    [
      429,
      {'Content-Type' => 'text/html', 'Retry-After' => retry_after.to_s},
      [<<-HTML
        <!DOCTYPE html>
        <html>
        <head>
          <title>Rate Limit Exceeded</title>
          <style>
            body { font-family: system-ui; max-width: 600px; margin: 100px auto; padding: 20px; text-align: center; }
            h1 { color: #dc2626; }
            p { color: #475569; line-height: 1.6; }
            a { color: #0ea5e9; text-decoration: none; }
          </style>
        </head>
        <body>
          <h1>⏰ Rate Limit Exceeded</h1>
          <p>You can only create <strong>3 Memflections per day</strong> to ensure fair usage for everyone.</p>
          <p>Please try again tomorrow, or <a href="mailto:support@memflect.com">contact us</a> if you need more access.</p>
        </body>
        </html>
      HTML
      ]
    ]
  end
end