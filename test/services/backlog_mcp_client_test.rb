require "test_helper"

class BacklogMcpClientTest < ActiveSupport::TestCase
  class StubTransportClient
    attr_reader :calls

    def initialize(response = nil, error: nil)
      @response = response
      @error = error
      @calls = []
    end

    def call_tool(name:, arguments:)
      @calls << [ name, arguments ]
      raise @error if @error
      @response
    end
  end

  def client_with(stub) = BacklogMcpClient.new(url: "http://mcp.test/mcp", client: stub)

  def tool_response(*texts, is_error: false, structured: nil)
    result = { "content" => texts.map { |t| { "type" => "text", "text" => t } }, "isError" => is_error }
    result["structuredContent"] = structured if structured
    { "result" => result }
  end

  test "calls the matching tool and returns text lines" do
    stub = StubTransportClient.new(tool_response("Game `Halo` - ID: 4"))

    result = client_with(stub).search_game(query: "halo")

    assert result.success?
    assert_equal [ "Game `Halo` - ID: 4" ], result.lines
    assert_equal [ [ "search_game", { query: "halo" } ] ], stub.calls
  end

  test "exposes structured content as data" do
    stub = StubTransportClient.new(tool_response("User `Ana` created - ID: 3", structured: { "id" => 3, "name" => "Ana" }))

    result = client_with(stub).create_user(name: "Ana", email: "ana@example.com")

    assert_equal({ "id" => 3, "name" => "Ana" }, result.data)
    assert_equal [ [ "create_user", { name: "Ana", email: "ana@example.com" } ] ], stub.calls
  end

  test "create_game calls the create_game tool" do
    stub = StubTransportClient.new(tool_response("ok"))

    client_with(stub).create_game(name: "Halo")

    assert_equal [ [ "create_game", { name: "Halo" } ] ], stub.calls
  end

  test "sends only the given arguments to add_to_backlog" do
    stub = StubTransportClient.new(tool_response("ok"))
    client = client_with(stub)

    client.add_to_backlog(user_id: 1, game_id: 2, status: "")
    client.add_to_backlog(user_id: 1, game_id: 2, status: "playing")

    assert_equal({ user_id: 1, game_id: 2 }, stub.calls.first.last)
    assert_equal({ user_id: 1, game_id: 2, status: "playing" }, stub.calls.last.last)
  end

  test "maps tool errors to Result#error" do
    stub = StubTransportClient.new(tool_response("User not found", is_error: true))

    result = client_with(stub).list_backlog(user_id: 99)

    assert_not result.success?
    assert_equal "User not found", result.error
  end

  test "maps transport failures to Result#error" do
    stub = StubTransportClient.new(error: Faraday::ConnectionFailed.new("refused"))

    result = client_with(stub).recommend_game(user_id: 1)

    assert_not result.success?
    assert_match(/Could not reach the MCP server/, result.error)
  end

  test "remove_from_backlog calls the remove_from_backlog tool" do
    stub = StubTransportClient.new(tool_response("removed"))

    client_with(stub).remove_from_backlog(user_id: 1, game_id: 2)

    assert_equal [ [ "remove_from_backlog", { user_id: 1, game_id: 2 } ] ], stub.calls
  end

  test "reports rejected credentials" do
    error = MCP::Client::RequestHandlerError.new("unauthorized", {}, error_type: :unauthorized)
    stub = StubTransportClient.new(error: error)

    result = client_with(stub).search_game(query: "x")

    assert_match(/rejected the credentials/, result.error)
  end

  test "default reads the URL from the environment" do
    ENV["MCP_SERVER_URL"] = "http://example.test/mcp"
    assert_equal "http://example.test/mcp", BacklogMcpClient.default.instance_variable_get(:@url)
  ensure
    ENV.delete("MCP_SERVER_URL")
  end
end
