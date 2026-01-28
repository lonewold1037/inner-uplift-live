class PagesController < ApplicationController
  # Allow anyone to see home, privacy, terms without logging in
  skip_before_action :authenticate_user!, only: [:home, :privacy, :terms]

  def home
  end

  def privacy
  end

  def terms
  end
end