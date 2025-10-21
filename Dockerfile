# Dockerfile
FROM ruby:3.4.1-slim

# Install necessary system libraries
RUN apt-get update -qq && apt-get install -y build-essential libpq-dev postgresql-client nodejs ffmpeg

# Set up a working directory
WORKDIR /rails

# Install gems
COPY Gemfile Gemfile.lock ./
RUN gem install bundler && bundle install

# Copy the rest of the application code
COPY . .

# Expose the port the Rails app runs on
EXPOSE 3000