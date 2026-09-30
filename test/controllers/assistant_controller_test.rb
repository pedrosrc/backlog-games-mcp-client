require "test_helper"

class AssistantControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "the assistant is the home page" do
    get root_path

    assert_response :success
    assert_select "h1", "Ask the assistant"
    assert_select "textarea[name=question]"
  end

  test "requires authentication" do
    sign_out
    get root_path
    assert_redirected_to new_session_path
    post assistant_path, params: { question: "hi" }
    assert_redirected_to new_session_path
  end

  test "shows the answer and the tools used" do
    mcp = { tool_definitions: [ { name: "list_backlog", description: "Lists", input_schema: { "properties" => { "user_id" => { "type" => "integer" } } } } ],
            list_backlog: FakeMcpClient.ok("Game `Halo` - Status: playing") }
    gemini = FakeGemini.new(FakeGemini.call("list_backlog"), FakeGemini.text("You are playing Halo."))

    stub_mcp(mcp) do |fake|
      stub_gemini(gemini) do
        post assistant_path, params: { question: "What am I playing?" }

        assert_response :success
        assert_select "section[aria-label=Answer]", /You are playing Halo\./
        assert_select "details summary", "Tools used (1)"
        assert_select "details code", /list_backlog/
        assert_select "textarea", "What am I playing?"
        assert_equal [ [ :list_backlog, { "user_id" => 1 } ] ], fake.calls
      end
    end
  end

  test "escapes model output" do
    stub_mcp do
      stub_gemini(FakeGemini.new(FakeGemini.text("<script>alert(1)</script>"))) do
        post assistant_path, params: { question: "hi" }

        assert_select "script", text: /alert/, count: 0
        assert_match "&lt;script&gt;", response.body
      end
    end
  end

  test "rejects a blank question without calling Gemini" do
    gemini = FakeGemini.new
    stub_mcp do
      stub_gemini(gemini) do
        post assistant_path, params: { question: "   " }
      end
    end

    assert_response :unprocessable_entity
    assert_match "Type a question first", response.body
    assert_empty gemini.requests
  end

  test "rejects a question that is too long" do
    stub_mcp do
      stub_gemini(FakeGemini.new) do
        post assistant_path, params: { question: "a" * (AssistantController::MAX_QUESTION_LENGTH + 1) }
      end
    end

    assert_response :unprocessable_entity
    assert_match "under #{AssistantController::MAX_QUESTION_LENGTH} characters", response.body
  end

  test "shows Gemini errors" do
    stub_mcp do
      stub_gemini(FakeGemini.new(GeminiClient::Error.new("GEMINI_API_KEY is not set"))) do
        post assistant_path, params: { question: "hi" }
      end
    end

    assert_response :unprocessable_entity
    assert_match "GEMINI_API_KEY is not set", response.body
  end
end
