require "test_helper"

class AssistantAgentTest < ActiveSupport::TestCase
  TOOLS = [
    { name: "create_user", description: "Creates a user", input_schema: { "properties" => { "name" => { "type" => "string" } }, "required" => [ "name" ] } },
    { name: "search_game", description: "Searches games", input_schema: { "properties" => { "query" => { "type" => "string", "description" => "Text" } }, "required" => [ "query" ] } },
    { name: "rate_game", description: "Rates a game",
      input_schema: { "properties" => { "user_id" => { "type" => "integer" }, "game_id" => { "type" => "integer" }, "rating" => { "type" => "number" } },
                      "required" => %w[user_id game_id rating] } },
    { name: "add_to_backlog", description: "Adds",
      input_schema: { "properties" => { "user_id" => { "type" => "integer" }, "game_id" => { "type" => "integer" },
                                        "status" => { "type" => "string", "enum" => %w[pending playing completed] } },
                      "required" => %w[game_id user_id] } }
  ].freeze

  def agent(mcp, gemini, user_id: 42) = AssistantAgent.new(mcp: mcp, gemini: gemini, mcp_user_id: user_id)

  def declarations(gemini) = gemini.requests.first[:tools].first[:functionDeclarations]

  test "returns the model's text when no tool is needed" do
    gemini = FakeGemini.new(FakeGemini.text("Hello!"))
    result = agent(FakeMcpClient.new(tool_definitions: TOOLS), gemini).call("hi")

    assert result.success?
    assert_equal "Hello!", result.answer
    assert_empty result.tool_calls
  end

  test "runs requested tools and sends the results back to the model" do
    found = FakeMcpClient.ok("Game `Hades` - ID: 9", data: { "games" => [ { "id" => 9, "name" => "Hades" } ] })
    mcp = FakeMcpClient.new(tool_definitions: TOOLS, search_game: found)
    gemini = FakeGemini.new(FakeGemini.call("search_game", { "query" => "hades" }), FakeGemini.text("Found Hades (ID 9)."))

    result = agent(mcp, gemini).call("find hades")

    assert_equal "Found Hades (ID 9).", result.answer
    assert_equal [ [ :search_game, { "query" => "hades" } ] ], mcp.calls
    assert_equal [ [ "search_game", { "query" => "hades" }, true ] ], result.tool_calls.map { |c| [ c.name, c.arguments, c.ok ] }

    # 2nd request carries: user question, the model's functionCall turn, and our functionResponse.
    contents = gemini.requests.last[:contents]
    assert_equal %w[user model user], contents.map { |c| c[:role] || c["role"] }
    response = contents.last[:parts].first[:functionResponse]
    assert_equal "search_game", response[:name]
    assert_equal "Game `Hades` - ID: 9", response[:response][:result]
    assert_equal({ "games" => [ { "id" => 9, "name" => "Hades" } ] }, response[:response][:data])
  end

  test "never exposes user_id to the model" do
    gemini = FakeGemini.new(FakeGemini.text("ok"))
    agent(FakeMcpClient.new(tool_definitions: TOOLS), gemini).call("hi")

    rate = declarations(gemini).find { |d| d[:name] == "rate_game" }
    assert_equal %w[game_id rating], rate[:parameters][:properties].keys.sort
    assert_equal %w[game_id rating], rate[:parameters][:required].sort
    assert_equal({ type: "INTEGER" }, rate[:parameters][:properties]["game_id"])
  end

  test "injects the signed-in user's ID and ignores one supplied by the model" do
    mcp = FakeMcpClient.new(tool_definitions: TOOLS, rate_game: FakeMcpClient.ok("rated"))
    gemini = FakeGemini.new(FakeGemini.call("rate_game", { "user_id" => 999, "game_id" => 9.0, "rating" => 8, "bogus" => "x" }), FakeGemini.text("done"))

    result = agent(mcp, gemini, user_id: 42).call("rate it")

    assert_equal [ [ :rate_game, { "game_id" => 9, "rating" => 8, "user_id" => 42 } ] ], mcp.calls
    assert_not result.tool_calls.first.arguments.key?("user_id"), "user_id is hidden from the transcript"
  end

  test "does not add user_id to tools that do not take one" do
    mcp = FakeMcpClient.new(tool_definitions: TOOLS, search_game: FakeMcpClient.ok("none"))
    agent(mcp, FakeGemini.new(FakeGemini.call("search_game", { "query" => "x" }), FakeGemini.text("ok"))).call("q")

    assert_equal [ [ :search_game, { "query" => "x" } ] ], mcp.calls
  end

  test "create_user is neither offered nor callable" do
    mcp = FakeMcpClient.new(tool_definitions: TOOLS)
    gemini = FakeGemini.new(FakeGemini.call("create_user", { "name" => "Evil" }), FakeGemini.text("refused"))

    result = agent(mcp, gemini).call("make me a user")

    assert_not_includes declarations(gemini).map { |d| d[:name] }, "create_user"
    assert_empty mcp.calls
    error = gemini.requests.last[:contents].last[:parts].first[:functionResponse][:response][:error]
    assert_match "Unknown tool", error
    assert_equal false, result.tool_calls.first.ok
  end

  test "tool errors are reported to the model" do
    mcp = FakeMcpClient.new(tool_definitions: TOOLS, rate_game: FakeMcpClient.failure("`rating` must be between 0 and 10"))
    gemini = FakeGemini.new(FakeGemini.call("rate_game", { "game_id" => 1, "rating" => 11 }), FakeGemini.text("Invalid rating"))

    result = agent(mcp, gemini).call("rate 11")

    assert_equal "Invalid rating", result.answer
    assert_equal "`rating` must be between 0 and 10", gemini.requests.last[:contents].last[:parts].first[:functionResponse][:response][:error]
    assert_equal false, result.tool_calls.first.ok
  end

  test "stops after too many tool rounds" do
    mcp = FakeMcpClient.new(tool_definitions: TOOLS, search_game: FakeMcpClient.ok("x"))
    gemini = FakeGemini.new(*Array.new(AssistantAgent::MAX_STEPS) { FakeGemini.call("search_game", { "query" => "x" }) })

    result = agent(mcp, gemini).call("loop")

    assert_not result.success?
    assert_match "too many steps", result.error
    assert_equal AssistantAgent::MAX_STEPS, result.tool_calls.size
  end

  test "reports Gemini failures" do
    gemini = FakeGemini.new(GeminiClient::Error.new("Gemini API error (HTTP 429)"))

    result = agent(FakeMcpClient.new(tool_definitions: TOOLS), gemini).call("hi")

    assert_equal "Gemini API error (HTTP 429)", result.error
  end

  test "reports a blocked prompt" do
    gemini = FakeGemini.new({ "promptFeedback" => { "blockReason" => "SAFETY" } })

    assert_match "SAFETY", agent(FakeMcpClient.new(tool_definitions: TOOLS), gemini).call("hi").error
  end

  test "reports an unavailable MCP server" do
    mcp = Object.new
    def mcp.tool_definitions = raise(BacklogMcpClient::Unavailable, "Could not reach the MCP server (X)")

    result = agent(mcp, FakeGemini.new).call("hi")

    assert_equal "Could not reach the MCP server (X)", result.error
  end
end
