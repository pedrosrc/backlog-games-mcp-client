require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  def signup_params(overrides = {})
    { user: { name: "New", email_address: "New@Example.com", password: "password123",
              password_confirmation: "password123" }.merge(overrides) }
  end

  test "new" do
    get new_registration_path
    assert_response :success
  end

  test "create makes the user on the MCP server and stores its ID" do
    created = FakeMcpClient.ok("User `New` created - ID: 7", data: { "id" => 7, "name" => "New" })

    stub_mcp(create_user: created) do |fake|
      assert_difference "User.count", 1 do
        post registration_path, params: signup_params
      end

      assert_equal [ [ :create_user, { name: "New", email: "new@example.com" } ] ], fake.calls
    end

    assert_redirected_to root_path
    assert cookies[:session_id]
    user = User.find_by!(email_address: "new@example.com")
    assert_equal 7, user.mcp_user_id
    assert_equal "New", user.name
  end

  test "create does not call the server when the form is invalid" do
    stub_mcp do |fake|
      assert_no_difference "User.count" do
        post registration_path, params: signup_params(password_confirmation: "different")
      end

      assert_empty fake.calls
    end

    assert_response :unprocessable_entity
  end

  test "create does not call the server for a duplicate email" do
    stub_mcp do |fake|
      post registration_path, params: signup_params(email_address: users(:one).email_address)

      assert_empty fake.calls
    end

    assert_response :unprocessable_entity
  end

  test "create shows the error when the MCP server fails" do
    stub_mcp(create_user: FakeMcpClient.failure("Could not reach the MCP server (ConnectionFailed)")) do
      assert_no_difference "User.count" do
        post registration_path, params: signup_params
      end
    end

    assert_response :unprocessable_entity
    assert_match "Could not reach the MCP server", response.body
  end

  test "create fails when the server returns no user ID" do
    stub_mcp(create_user: FakeMcpClient.ok("User created")) do
      assert_no_difference "User.count" do
        post registration_path, params: signup_params
      end
    end

    assert_response :unprocessable_entity
  end
end
