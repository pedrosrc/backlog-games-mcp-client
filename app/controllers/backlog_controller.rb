class BacklogController < ApplicationController
  def show
    @result = mcp.list_backlog(user_id: Current.user.mcp_user_id.to_i)
    return unless @result.success?

    @filter = BacklogFilter.new(params.permit(:status, :rating))
    @items = Array(@result.data&.dig("items"))
    @visible_items = @filter.apply(@items)
  end

  def create
    result = mcp.add_to_backlog(user_id: Current.user.mcp_user_id.to_i, game_id: params[:game_id].to_i, status: params[:status])
    redirect_back_or_to backlog_path, **flash_for(result)
  end

  def destroy
    result = mcp.remove_from_backlog(user_id: Current.user.mcp_user_id.to_i, game_id: params[:game_id].to_i)
    redirect_back_or_to backlog_path, **flash_for(result)
  end
end
