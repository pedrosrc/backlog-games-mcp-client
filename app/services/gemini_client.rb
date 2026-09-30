class GeminiClient
  class Error < StandardError; end

  BASE_URL = "https://generativelanguage.googleapis.com/v1beta".freeze
  DEFAULT_MODEL = ENV["GEMINI_MODEL"].freeze

  def self.default
    new(api_key: ENV["GEMINI_API_KEY"], model: ENV["GEMINI_MODEL"].presence || DEFAULT_MODEL)
  end

  def initialize(api_key:, model: DEFAULT_MODEL, connection: nil)
    @api_key = api_key.presence
    @model = model
    @connection = connection
  end

  def generate_content(contents:, tools: nil, system_instruction: nil)
    raise Error, "GEMINI_API_KEY is not set" if @api_key.nil?

    payload = { contents: contents }
    payload[:tools] = tools if tools.present?
    payload[:systemInstruction] = { parts: [ { text: system_instruction } ] } if system_instruction

    response = connection.post("models/#{@model}:generateContent") do |request|
      request.headers["x-goog-api-key"] = @api_key
      request.headers["Content-Type"] = "application/json"
      request.body = payload.to_json
    end

    body = parse(response.body)
    raise Error, error_message(response.status, body) unless response.success?

    body
  rescue Faraday::Error => e
    Rails.logger.error("[GeminiClient] #{e.class}: #{e.message}")
    raise Error, "Could not reach the Gemini API (#{e.class.name.demodulize})"
  end

  private

  def connection
    @connection ||= Faraday.new(url: BASE_URL, request: { timeout: 60, open_timeout: 10 })
  end

  def parse(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError
    {}
  end

  def error_message(status, body)
    detail = body.dig("error", "message").to_s.truncate(200)
    "Gemini API error (HTTP #{status})#{": #{detail}" if detail.present?}"
  end
end
