# Answers a question with Gemini, letting the model call the MCP server's tools.
#
# Loop: send the conversation and the tool declarations to Gemini; while it asks
# for tool calls, run them against the MCP server and send the results back.
#
# Safety rules enforced here, not left to the model:
# - `user_id` is never exposed to the model; it is injected from the signed-in user.
# - Tools in HIDDEN_TOOLS are not offered and are refused if requested anyway.
class AssistantAgent
  MAX_STEPS = 6
  HIDDEN_TOOLS = %w[create_user].freeze
  USER_ID_ARGUMENT = "user_id".freeze

  SYSTEM_INSTRUCTION = <<~TEXT.freeze
    You are the assistant of a video game backlog app. Use the provided tools to read and change the
    signed-in user's backlog, ratings and recommendations, and to search the game catalog.
    - The user is already identified: never ask for a user ID.
    - Tools take game IDs. Use search_game to find a game's ID before adding, rating or removing it.
    - If a search returns several plausible games, ask which one the user means instead of guessing.
    - Only change data (add, rate, remove, create) when the user asks for it.
    - Never invent games or ratings: base answers on tool results.
    - Answer in the user's language, briefly.
  TEXT

  ToolCall = Struct.new(:name, :arguments, :ok, keyword_init: true)
  Result = Struct.new(:answer, :tool_calls, :error, keyword_init: true) do
    def success? = error.nil?
  end

  def initialize(mcp:, gemini:, mcp_user_id:)
    @mcp = mcp
    @gemini = gemini
    @mcp_user_id = mcp_user_id
  end

  def call(question)
    @tool_calls = []
    definitions = @mcp.tool_definitions.reject { |tool| HIDDEN_TOOLS.include?(tool[:name]) }.index_by { |tool| tool[:name] }
    declarations = definitions.values.map { |tool| declaration(tool) }
    contents = [ { role: "user", parts: [ { text: question } ] } ]

    MAX_STEPS.times do
      response = @gemini.generate_content(contents: contents, tools: [ { functionDeclarations: declarations } ],
                                          system_instruction: SYSTEM_INSTRUCTION)
      content = response.dig("candidates", 0, "content")
      return failure(no_answer_reason(response)) if content.nil?

      parts = Array(content["parts"])
      calls = parts.filter_map { |part| part["functionCall"] }
      return Result.new(answer: parts.filter_map { |part| part["text"] }.join.strip.presence || "(no answer)", tool_calls: @tool_calls) if calls.empty?

      # Echo the model turn unchanged (keeps any thought signatures), then answer every call.
      contents << content
      contents << { role: "user", parts: calls.map { |tool_call| function_response(tool_call, definitions) } }
    end

    failure("The assistant needed too many steps. Try a more specific question.")
  rescue GeminiClient::Error, BacklogMcpClient::Unavailable => e
    failure(e.message)
  end

  private

  def failure(message) = Result.new(error: message, tool_calls: @tool_calls)

  def no_answer_reason(response)
    block = response.dig("promptFeedback", "blockReason")
    block ? "Gemini blocked the request (#{block})" : "Gemini did not return an answer"
  end

  def function_response(tool_call, definitions)
    name = tool_call["name"].to_s
    definition = definitions[name]

    payload =
      if definition.nil?
        record(name, {}, false)
        { error: "Unknown tool `#{name}`" }
      else
        arguments = build_arguments(definition, tool_call["args"])
        result = @mcp.call_tool(name, arguments)
        record(name, arguments.except(USER_ID_ARGUMENT), result.success?)
        result.success? ? { result: result.lines.join("\n"), data: result.data }.compact : { error: result.error }
      end

    { functionResponse: { name: name, response: payload } }
  end

  def record(name, arguments, ok) = @tool_calls << ToolCall.new(name: name, arguments: arguments, ok: ok)

  def build_arguments(definition, raw)
    properties = properties_of(definition)
    arguments = (raw || {}).to_h.stringify_keys.slice(*properties.keys).except(USER_ID_ARGUMENT)
    arguments.each { |key, value| arguments[key] = value.to_i if properties.dig(key, "type") == "integer" && value.is_a?(Numeric) }
    arguments[USER_ID_ARGUMENT] = @mcp_user_id if properties.key?(USER_ID_ARGUMENT)
    arguments
  end

  def properties_of(definition) = (definition[:input_schema] || {}).deep_stringify_keys.fetch("properties", {})

  # MCP tool -> Gemini function declaration (OpenAPI subset), minus the server-controlled user_id.
  def declaration(tool)
    schema = (tool[:input_schema] || {}).deep_stringify_keys
    properties = schema.fetch("properties", {}).except(USER_ID_ARGUMENT).transform_values { |property| gemini_schema(property) }
    required = Array(schema["required"]) - [ USER_ID_ARGUMENT ]

    parameters = { type: "OBJECT", properties: properties }
    parameters[:required] = required if required.any?
    declaration = { name: tool[:name], description: tool[:description].to_s }
    declaration[:parameters] = parameters if properties.any?
    declaration
  end

  def gemini_schema(property)
    result = { type: property["type"].to_s.upcase }
    result[:description] = property["description"] if property["description"]
    result[:enum] = property["enum"] if property["enum"]
    result
  end
end
