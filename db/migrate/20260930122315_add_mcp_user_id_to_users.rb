class AddMcpUserIdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :mcp_user_id, :integer
  end
end
