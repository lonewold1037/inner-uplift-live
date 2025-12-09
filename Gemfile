source "https://rubygems.org"

ruby "3.4.7"

# Framework
gem "rails", "~> 7.2.2"

# Core stack
gem "strong_migrations"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem "bootsnap", require: false
gem "devise"
gem "multipart-post"

# Background jobs
gem "good_job"

# ActivStorage validations (for content_type)
gem "active_storage_validations"

# Platform-specific
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Deployment helpers
gem "kamal", require: false
gem "thruster", require: false

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
  gem "foreman"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end

gem "vite_rails", "~> 3.0"
gem "solid_cache"
gem "redis"
gem "aws-sdk-s3", require: false

# Stripe for payments
gem 'stripe', '~> 12.0'

gem 'rack-attack'
