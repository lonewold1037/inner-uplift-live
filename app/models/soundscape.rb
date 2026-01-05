class Soundscape < ApplicationRecord
  CATEGORIES = [
    "Oceania", "Epic Motivational", "Zen Meditation", "Lo-Fi Chill", "Cosmic Dream",
    "Cinematic Piano", "90s Hip-Hop", "80s Love Songs", "Dream Pop", "Uplifting Choir",
    "Inspiring Synth"
  ].freeze

  # Comment out categories to hide them from users
  ENABLED_CATEGORIES = [
    # "Oceania",
    "Epic Motivational",
    "Zen Meditation",
    "Lo-Fi Chill",
    # "Cosmic Dream",
    "Cinematic Piano",
    "90s Hip-Hop",
    "80s Love Songs",
    "Dream Pop",
    "Uplifting Choir",
    "Inspiring Synth"
  ].freeze

  has_one_attached :audio_file

  validates :name, presence: true, uniqueness: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
end
