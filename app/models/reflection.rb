class Reflection < ApplicationRecord
  include Turbo::Broadcastable

  # Master list for the AI's writing tone
  STYLES = [
    "REFLECTIVE",
    "MOTIVATIONAL",
    "HEARTFELT",
    "HUMOROUS",
    "PEACEFUL",
    "EPIC",
    "GRATEFUL"
  ].freeze

  belongs_to :user, optional: true
  belongs_to :soundscape, optional: true

  # Attachments
  has_one_attached :voice_recording
  has_one_attached :preview_audio
  has_one_attached :full_audio
  has_one_attached :final_audio
  has_one_attached :extended_audio
  has_one_attached :cover_image

  # Validations
  validates :style, inclusion: { in: STYLES }, allow_nil: true

  MODES = ["self", "gift"].freeze
  validates :mode, inclusion: { in: MODES }, allow_nil: true

  # validates :voice_recording, content_type: %w[audio/mpeg audio/webm audio/mp4 video/mp4], allow_blank: true
  validates :preview_audio,   content_type: %w[audio/mpeg audio/mpeg], allow_blank: true
  validates :full_audio,      content_type: %w[audio/mpeg audio/mpeg], allow_blank: true
  validates :final_audio,     content_type: %w[audio/mpeg audio/mpeg], allow_blank: true

  # ========== MEMCARD SHARING ==========
  MEMCARD_TOKEN_LENGTH = 16

  scope :with_active_memcard, -> { where(memcard_enabled: true).where.not(memcard_token: nil) }

  def enable_memcard!
    update!(
      memcard_token: generate_memcard_token,
      memcard_enabled: true,
      memcard_enabled_at: Time.current
    )
  end

  def disable_memcard!
    update!(
      memcard_enabled: false,
      memcard_token: nil
    )
  end

  def memcard_url
    return nil unless memcard_enabled? && memcard_token.present?
    Rails.application.routes.url_helpers.memcard_url(token: memcard_token, host: ENV.fetch("APP_HOST", "memflect.com"))
  end

  private

  def generate_memcard_token
    loop do
      token = SecureRandom.urlsafe_base64(MEMCARD_TOKEN_LENGTH).tr("-_", "").first(MEMCARD_TOKEN_LENGTH)
      break token unless self.class.exists?(memcard_token: token)
    end
  end
end