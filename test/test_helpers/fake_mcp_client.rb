# Stand-in for BacklogMcpClient: records calls and returns canned results.
class FakeMcpClient
  attr_reader :calls

  def initialize(results = {})
    @results = results
    @calls = []
  end

  %i[create_user create_game search_game add_to_backlog remove_from_backlog list_backlog rate_game recommend_game].each do |name|
    define_method(name) do |**args|
      @calls << [ name, args ]
      @results.fetch(name) { BacklogMcpClient::Result.new(lines: []) }
    end
  end

  def tool_definitions = @results.fetch(:tool_definitions) { [] }

  def call_tool(name, arguments)
    @calls << [ name.to_sym, arguments ]
    @results.fetch(name.to_sym) { BacklogMcpClient::Result.new(lines: []) }
  end

  def self.ok(*lines, data: nil) = BacklogMcpClient::Result.new(lines: lines, data: data)
  def self.failure(message) = BacklogMcpClient::Result.new(lines: [], error: message)
end

module McpStubHelper
  def stub_mcp(results = {})
    fake = FakeMcpClient.new(results)
    original = BacklogMcpClient.method(:default)
    BacklogMcpClient.define_singleton_method(:default) { fake }
    yield fake
  ensure
    BacklogMcpClient.define_singleton_method(:default, original)
  end
end

# Scripted Gemini: returns the queued responses in order and records the requests.
class FakeGemini
  attr_reader :requests

  def initialize(*responses)
    @responses = responses
    @requests = []
  end

  def generate_content(**request)
    @requests << request
    response = @responses.shift || raise("FakeGemini has no more responses")
    raise response if response.is_a?(Exception)
    response
  end

  def self.text(text) = { "candidates" => [ { "content" => { "role" => "model", "parts" => [ { "text" => text } ] } } ] }

  def self.call(name, args = {}) = { "candidates" => [ { "content" => { "role" => "model", "parts" => [ { "functionCall" => { "name" => name, "args" => args } } ] } } ] }
end

module GeminiStubHelper
  def stub_gemini(fake)
    original = GeminiClient.method(:default)
    GeminiClient.define_singleton_method(:default) { fake }
    yield fake
  ensure
    GeminiClient.define_singleton_method(:default, original)
  end
end

ActiveSupport::TestCase.include McpStubHelper
ActiveSupport::TestCase.include GeminiStubHelper
ActionDispatch::IntegrationTest.include McpStubHelper
ActionDispatch::IntegrationTest.include GeminiStubHelper
