require "test_helper"

class McpPagesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "pages require authentication" do
    sign_out
    [ root_path, backlog_path, recommendations_path ].each do |path|
      get path
      assert_redirected_to new_session_path
    end
    post ratings_path, params: { game_id: 1, rating: 5 }
    assert_redirected_to new_session_path
    delete backlog_item_path(game_id: 1)
    assert_redirected_to new_session_path
  end

  test "search lists the games from the structured content" do
    found = FakeMcpClient.ok("Game `Halo` - ID: 4", data: { "games" => [ { "id" => 4, "name" => "Halo" } ] })

    stub_mcp(search_game: found) do |fake|
      get games_path, params: { query: "halo" }

      assert_response :success
      assert_select "strong", "Halo"
      assert_select "input[name=game_id][value='4']", count: 2
      assert_equal [ [ :search_game, { query: "halo" } ] ], fake.calls
    end
  end

  test "search shows the no-results message" do
    empty = FakeMcpClient.ok("No games found for `zzz`", data: { "games" => [] })

    stub_mcp(search_game: empty) do
      get games_path, params: { query: "zzz" }

      assert_response :success
      assert_match "No games found", response.body
      assert_select "input[type=submit][value*='zzz']"
    end
  end

  test "creating a game calls the server and searches for it" do
    stub_mcp(create_game: FakeMcpClient.ok("Game `Halo` created - ID: 4")) do |fake|
      post games_path, params: { name: " Halo " }

      assert_redirected_to games_path(query: "Halo")
      assert_equal "Game `Halo` created - ID: 4", flash[:notice]
      assert_equal [ [ :create_game, { name: "Halo" } ] ], fake.calls
    end
  end

  test "search shows MCP errors" do
    stub_mcp(search_game: FakeMcpClient.failure("Could not reach the MCP server (ConnectionFailed)")) do
      get games_path, params: { query: "halo" }

      assert_match "Could not reach the MCP server", response.body
    end
  end

  test "blank search does not call the server" do
    stub_mcp do |fake|
      get games_path

      assert_response :success
      assert_empty fake.calls
    end
  end

  BACKLOG = FakeMcpClient.ok(
    "Game `Halo` - Status: playing", "Game `Zelda` - Status: completed", "Game `Tetris` - Status: pending",
    data: { "items" => [
      { "game_id" => 4, "name" => "Halo", "status" => "playing", "rating" => 6.5 },
      { "game_id" => 5, "name" => "Zelda", "status" => "completed", "rating" => 10.0 },
      { "game_id" => 6, "name" => "Tetris", "status" => "pending", "rating" => nil }
    ] }
  )

  test "backlog lists items with status badges, ratings and uses the signed-in user's MCP id" do
    stub_mcp(list_backlog: BACKLOG) do |fake|
      get backlog_path

      assert_select "li", 3
      assert_select "li span.font-medium", "Halo"
      assert_select "span.bg-orange-100", "pending"
      assert_select "span.bg-yellow-100", "playing"
      assert_select "span.bg-green-100", "completed"
      assert_select "input[name=rating][value='6.5']"
      assert_select "input[name=rating][value='10']"
      assert_equal [ [ :list_backlog, { user_id: 1 } ] ], fake.calls
    end
  end

  test "backlog filters by status" do
    stub_mcp(list_backlog: BACKLOG) do
      get backlog_path, params: { status: "completed" }

      assert_select "li", 1
      assert_select "li span.font-medium", "Zelda"
      assert_select "a", "Clear"
    end
  end

  test "backlog filters by rating" do
    stub_mcp(list_backlog: BACKLOG) do
      get backlog_path, params: { rating: "unrated" }
      assert_select "li span.font-medium", text: "Tetris", count: 1
      assert_select "li", 1

      get backlog_path, params: { rating: "7" }
      assert_select "li span.font-medium", "Zelda"
      assert_select "li", 1
    end
  end

  test "backlog says when no game matches the filters" do
    stub_mcp(list_backlog: BACKLOG) do
      get backlog_path, params: { status: "pending", rating: "9" }

      assert_select "li", 0
      assert_match "No games match these filters", response.body
    end
  end

  test "empty backlog shows the server message" do
    empty = FakeMcpClient.ok("Backlog is empty for user `One`", data: { "items" => [] })

    stub_mcp(list_backlog: empty) do
      get backlog_path

      assert_match "Backlog is empty for user", response.body
      assert_select "li", 0
    end
  end

  test "backlog shows MCP errors" do
    stub_mcp(list_backlog: FakeMcpClient.failure("Could not reach the MCP server (X)")) do
      get backlog_path

      assert_match "Could not reach the MCP server", response.body
    end
  end

  test "removing a game calls the server and flashes the result" do
    stub_mcp(remove_from_backlog: FakeMcpClient.ok("Game `Halo` removed from backlog")) do |fake|
      delete backlog_item_path(game_id: 4)

      assert_redirected_to backlog_path
      assert_equal "Game `Halo` removed from backlog", flash[:notice]
      assert_equal [ [ :remove_from_backlog, { user_id: 1, game_id: 4 } ] ], fake.calls
    end
  end

  test "removing returns to the filtered page" do
    stub_mcp(remove_from_backlog: FakeMcpClient.ok("ok")) do
      delete backlog_item_path(game_id: 4), headers: { "HTTP_REFERER" => backlog_url(status: "playing") }

      assert_redirected_to backlog_url(status: "playing")
    end
  end

  test "removing flashes server errors" do
    stub_mcp(remove_from_backlog: FakeMcpClient.failure("Game `Halo` is not in the backlog")) do
      delete backlog_item_path(game_id: 4)

      assert_equal "Game `Halo` is not in the backlog", flash[:alert]
    end
  end

  test "editing a rating from the backlog returns to the backlog" do
    stub_mcp(rate_game: FakeMcpClient.ok("Game `Halo` rated 8.0 by user `One`")) do |fake|
      post ratings_path, params: { game_id: 4, rating: 8 }, headers: { "HTTP_REFERER" => backlog_url(rating: "5") }

      assert_redirected_to backlog_url(rating: "5")
      assert_equal [ [ :rate_game, { user_id: 1, game_id: 4, rating: 8.0 } ] ], fake.calls
    end
  end

  test "adding to the backlog flashes the result" do
    stub_mcp(add_to_backlog: FakeMcpClient.ok("Game `Halo` added to backlog")) do |fake|
      post backlog_path, params: { game_id: 4, status: "playing" }

      assert_redirected_to backlog_path
      assert_equal "Game `Halo` added to backlog", flash[:notice]
      assert_equal [ [ :add_to_backlog, { user_id: 1, game_id: 4, status: "playing" } ] ], fake.calls
    end
  end

  test "rating flashes errors from the server" do
    stub_mcp(rate_game: FakeMcpClient.failure("`rating` must be between 0 and 10")) do
      post ratings_path, params: { game_id: 4, rating: 11 }

      assert_redirected_to games_path
      assert_equal "`rating` must be between 0 and 10", flash[:alert]
    end
  end

  test "recommendations" do
    stub_mcp(recommend_game: FakeMcpClient.ok("Here are some games you might like: Halo")) do
      get recommendations_path

      assert_match "Halo", response.body
    end
  end
end
