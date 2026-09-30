class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  # ID of this person's User record in backlog-games-mcp-server.
  # Set right after the user is created on the server, so sign-up validates the rest first (`valid?(:signup)`).
  validates :mcp_user_id, presence: true, numericality: { only_integer: true, greater_than: 0 },
                          unless: -> { validation_context == :signup }
  validates :name, presence: true
end
