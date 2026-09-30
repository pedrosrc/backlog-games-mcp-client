require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "requires a positive integer mcp_user_id" do
    user = User.new(name: "A", email_address: "a@example.com", password: "password123")

    assert_not user.valid?
    assert user.valid?(:signup), "mcp_user_id is only assigned after the server call"
    user.mcp_user_id = 0
    assert_not user.valid?
    user.mcp_user_id = 3
    assert user.valid?
  end

  test "requires a name" do
    assert_not User.new(email_address: "a@example.com", password: "password123", mcp_user_id: 3).valid?
  end

  test "requires a password of at least 8 characters" do
    user = User.new(name: "A", email_address: "a@example.com", password: "short", mcp_user_id: 3)

    assert_not user.valid?
  end
end
