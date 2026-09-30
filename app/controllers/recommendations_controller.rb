class RecommendationsController < ApplicationController
  def show
    @result = mcp.recommend_game(user_id: Current.user.mcp_user_id)
  end
end
