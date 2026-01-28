class PagesController < ApplicationController
  # Allow anyone to see home, privacy, terms without logging in
  skip_before_action :authenticate_user!, only: [:home, :privacy, :terms]

  def home
  end

  def privacy
  end

  def terms
  end

  def accept_cookies
    cookies[:cookie_consent] = { value: "accepted", expires: 1.year.from_now }
    redirect_back(fallback_location: root_path)
  end
end