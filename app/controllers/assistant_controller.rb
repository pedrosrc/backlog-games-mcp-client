class AssistantController < ApplicationController
  MAX_QUESTION_LENGTH = 1000

  rate_limit to: 15, within: 1.minute, only: :create, with: -> { redirect_to root_path, alert: "Too many questions. Try again in a minute." }

  def show
  end

  def create
    @question = params[:question].to_s.strip

    if @question.blank?
      @error = "Type a question first."
    elsif @question.length > MAX_QUESTION_LENGTH
      @error = "Keep the question under #{MAX_QUESTION_LENGTH} characters."
    else
      result = AssistantAgent.new(mcp: mcp, gemini: GeminiClient.default, mcp_user_id: Current.user.mcp_user_id).call(@question)
      @answer = result.answer
      @tool_calls = result.tool_calls
      @error = result.error
    end

    render :show, status: (@error ? :unprocessable_entity : :ok)
  end
end
