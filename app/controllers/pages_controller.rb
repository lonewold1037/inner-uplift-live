class PagesController < ApplicationController
  # We skip the login requirement for the homepage
  skip_before_action :authenticate_user!, only: [:home]

  def home
  end

  def about
  end

  def contact
  end
end