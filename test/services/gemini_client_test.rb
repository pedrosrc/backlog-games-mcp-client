require "test_helper"

class GeminiClientTest < ActiveSupport::TestCase
  def connection(status: 200, body: {}, &block)
    Faraday.new(url: GeminiClient::BASE_URL) do |f|
      f.adapter :test do |stub|
        stub.post("/v1beta/models/gemini-test:generateContent") do |env|
          block&.call(env)
          [ status, { "Content-Type" => "application/json" }, body.is_a?(String) ? body : body.to_json ]
        end
      end
    end
  end

  def client(**options) = GeminiClient.new(api_key: "key-123", model: "gemini-test", **options)

  test "posts contents, tools and system instruction with the key in a header" do
    seen = nil
    conn = connection(body: { "candidates" => [] }) { |env| seen = { body: env.body, headers: env.request_headers.to_h, url: env.url.to_s } }

    result = client(connection: conn).generate_content(
      contents: [ { role: "user", parts: [ { text: "hi" } ] } ],
      tools: [ { functionDeclarations: [ { name: "x" } ] } ],
      system_instruction: "be brief"
    )

    assert_equal({ "candidates" => [] }, result)
    assert_equal "key-123", seen[:headers]["x-goog-api-key"]
    assert_not_includes seen[:url], "key-123"
    payload = JSON.parse(seen[:body])
    assert_equal "hi", payload.dig("contents", 0, "parts", 0, "text")
    assert_equal "x", payload.dig("tools", 0, "functionDeclarations", 0, "name")
    assert_equal "be brief", payload.dig("systemInstruction", "parts", 0, "text")
  end

  test "raises when the API key is missing" do
    error = assert_raises(GeminiClient::Error) { GeminiClient.new(api_key: "").generate_content(contents: []) }

    assert_match "GEMINI_API_KEY", error.message
  end

  test "raises with the API error message on failure" do
    conn = connection(status: 429, body: { "error" => { "message" => "Quota exceeded" } })

    error = assert_raises(GeminiClient::Error) { client(connection: conn).generate_content(contents: []) }

    assert_equal "Gemini API error (HTTP 429): Quota exceeded", error.message
  end

  test "raises on an unparseable error body" do
    error = assert_raises(GeminiClient::Error) { client(connection: connection(status: 502, body: "<html>")).generate_content(contents: []) }

    assert_equal "Gemini API error (HTTP 502)", error.message
  end

  test "default reads the model from the environment" do
    ENV["GEMINI_MODEL"] = "gemini-custom"
    assert_equal "gemini-custom", GeminiClient.default.instance_variable_get(:@model)
  ensure
    ENV.delete("GEMINI_MODEL")
  end
end
