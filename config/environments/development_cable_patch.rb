# Add these lines to config/environments/development.rb

# Enable ActionCable in development
config.action_cable.disable_request_forgery_protection = true

# Set the ActionCable URL for GitHub Codespaces
config.action_cable.url = "ws://localhost:3000/cable"

# Allow ActionCable requests from any origin in development
config.action_cable.allowed_request_origins = [ /http:\/\/.*/, /https:\/\/.*/ ]
