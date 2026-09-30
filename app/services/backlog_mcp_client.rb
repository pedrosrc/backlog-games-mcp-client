# Talks to backlog-games-mcp-server over MCP (Streamable HTTP).
#
# Each method calls the matching MCP tool and returns a Result. Tool errors
# (`is_error`) and transport errors are reported through Result#error, never raised.
class BacklogMcpClient
  # `lines` are the tool's text output; `data` is its structuredContent (a Hash), when it returns one.
  Result = Struct.new(:lines, :data, :error, keyword_init: true) do
    def success? = error.nil?
  end

  class Unavailable < StandardError; end

  class << self
    def default
      new(url: ENV.fetch("MCP_SERVER_URL", "http://localhost:3001/mcp"), token: ENV["MCP_SERVER_TOKEN"].presence)
    end
  end

  def initialize(url:, token: nil, client: nil)
    @url = url
    @token = token
    @client = client
  end

  def create_user(name:, email:) = call("create_user", name: name, email: email)

  def create_game(name:) = call("create_game", name: name)

  def search_game(query:) = call("search_game", query: query)

  def add_to_backlog(user_id:, game_id:, status: nil)
    call("add_to_backlog", { user_id: user_id, game_id: game_id, status: status.presence }.compact)
  end

  def remove_from_backlog(user_id:, game_id:) = call("remove_from_backlog", user_id: user_id, game_id: game_id)

  def list_backlog(user_id:) = call("list_backlog", user_id: user_id)

  def rate_game(user_id:, game_id:, rating:) = call("rate_game", user_id: user_id, game_id: game_id, rating: rating)

  def recommend_game(user_id:) = call("recommend_game", user_id: user_id)

  # Tools the server offers: [{ name:, description:, input_schema: }]. Raises Unavailable.
  def tool_definitions
    client.tools.map { |tool| { name: tool.name, description: tool.description, input_schema: tool.input_schema } }
  rescue MCP::Client::ServerError, MCP::Client::RequestHandlerError, Faraday::Error => e
    Rails.logger.error("[BacklogMcpClient] tools/list failed: #{e.class}: #{e.message}")
    raise Unavailable, failure_message(e)
  end

  # Calls any tool by name (used by the assistant).
  def call_tool(name, arguments) = call(name, arguments)

  private

  def call(tool, arguments)
    response = client.call_tool(name: tool, arguments: arguments)
    result = response["result"] || {}
    lines = Array(result["content"]).filter_map { |item| item["text"] }

    if result["isError"]
      Result.new(lines: [], error: lines.join(" ").presence || "The MCP server returned an error")
    else
      Result.new(lines: lines, data: result["structuredContent"])
    end
  rescue MCP::Client::ServerError, MCP::Client::RequestHandlerError, Faraday::Error => e
    Rails.logger.error("[BacklogMcpClient] #{tool} failed: #{e.class}: #{e.message}")
    Result.new(lines: [], error: failure_message(e))
  end

  def failure_message(error)
    if error.respond_to?(:error_type) && error.error_type == :unauthorized
      "The MCP server rejected the credentials (check MCP_SERVER_TOKEN)"
    else
      "Could not reach the MCP server (#{error.class.name.demodulize})"
    end
  end

  def client
    @client ||= begin
      headers = @token ? { "Authorization" => "Bearer #{@token}" } : {}
      MCP::Client.new(transport: MCP::Client::HTTP.new(url: @url, headers: headers))
    end
  end
end
