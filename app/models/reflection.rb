class Reflection < ApplicationRecord
  include Turbo::Broadcastable

  # Master list for the AI's writing tone
  STYLES = [
    "Calm",
    "Hard-hitting",
    "Funny",
    "Out of this world",
    "Exciting",
    "Meditative"
  ].freeze

  belongs_to :user, optional: true
  belongs_to :soundscape, optional: true

  # Attachments
  has_one_attached :voice_recording
  has_one_attached :preview_audio
  has_one_attached :full_audio
  has_one_attached :final_audio
  has_one_attached :extended_audio

  # Validations
  validates :style, inclusion: { in: STYLES }, allow_nil: true

  validates :voice_recording, content_type: %w[audio/mpeg audio/mpeg audio/webm], allow_blank: true
  validates :preview_audio,   content_type: %w[audio/mpeg audio/mpeg], allow_blank: true
  validates :full_audio,      content_type: %w[audio/mpeg audio/mpeg], allow_blank: true
  validates :final_audio,     content_type: %w[audio/mpeg audio/mpeg], allow_blank: true
end