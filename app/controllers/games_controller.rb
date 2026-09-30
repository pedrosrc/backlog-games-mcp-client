class GamesController < ApplicationController
  def index
    @query = params[:query].to_s.strip
    return if @query.blank?

    @result = mcp.search_game(query: @query)
    @games = Array(@result.data&.dig("games")) if @result.success?
  end

  def create
    result = mcp.create_game(name: params[:name].to_s.strip)
    redirect_to games_path(query: params[:name].to_s.strip), **flash_for(result)
  end
end
