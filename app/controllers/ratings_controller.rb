class RatingsController < ApplicationController
  def create
    result = mcp.rate_game(user_id: Current.user.mcp_user_id.to_i, game_id: params[:game_id].to_i, rating: params[:rating].to_f)
    redirect_back_or_to games_path, **flash_for(result)
  end
end
