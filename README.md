# Backlog Games MCP Client

A Rails 8 web app (with built-in authentication) that is the client of
[backlog-games-mcp-server](https://github.com/pedrosrc/backlog-games-mcp-server). Signed-in users can
search games, add them to their backlog, rate them and get recommendations; every
action is an MCP tool call made with the `mcp` gem's HTTP client.

## How it works

```
Browser ──> Rails controllers ──> BacklogMcpClient ──MCP (Streamable HTTP)──> backlog-games-mcp-server
```

- **Authentication:** Rails 8 generator (`User`, `Session`, password reset) plus a
  sign-up page. Every page requires a session except sign in, sign up and password reset.
- **`BacklogMcpClient`** (`app/services/backlog_mcp_client.rb`): one method per
  server tool (`create_user`, `remove_from_backlog`, `create_game`, `search_game`, `add_to_backlog`, `list_backlog`, `rate_game`,
  `recommend_game`). It returns a `Result` with the text lines, or an `error`
  when the tool reports `is_error` or the server is unreachable.
- **User mapping:** the server identifies people by its own `user_id`. On sign-up
  the client calls the server's `create_user` tool (name and email; the
  password never leaves the client) and stores the returned ID as
  `mcp_user_id`; it is sent with every later call. The local account is only saved
  after the server call succeeds.
- **Structured results:** IDs are read from the tools' `structuredContent`
  (`Result#data`), not parsed from text. `search_game` returns
  `{ "games": [{ "id", "name" }] }` and `create_user` / `create_game` return `{ "id", "name" }`.
- **Assistant (home page):** the user asks a question in plain language and Gemini
  answers, calling the MCP server's tools when it needs data or to make a change.
  `GeminiClient` wraps the `generateContent` REST API and `AssistantAgent` runs the
  loop (send question and tool declarations, run the tool calls Gemini asks for, send
  the results back, at most 6 rounds). The tool declarations are built from the
  server's `tools/list`, so new server tools are picked up automatically. Enforced in
  code, not left to the model: `user_id` is hidden from Gemini and always injected
  from the signed-in user, and `create_user` is never offered. The page lists the tools
  that were used. Questions are limited to 1000 characters and 15 per minute per IP.
- **My backlog:** items come from `list_backlog`'s `structuredContent`
  (`game_id`, `name`, `status`, `rating`). Filtering by status and minimum rating is
  done in the client (`BacklogFilter`); ratings are edited with `rate_game` and games
  removed with `remove_from_backlog`. Status colors: pending orange, playing yellow,
  completed green.
- **Games:** when a search finds nothing, the page offers to create the game with
  the server's `create_game` tool.

## Setup

```bash
bundle install
cp .env.example .env     # then edit it
bin/rails db:setup
bin/dev                  # or: bin/rails s   (http://localhost:3000)
```

| Variable                                     | Purpose                                              |
| -------------------------------------------- | ---------------------------------------------------- |
| `DEV_POSTGRES_HOST/USER/PASSWORD`            | PostgreSQL connection (dev and test)                 |
| `MCP_SERVER_URL`                             | MCP endpoint, default `http://localhost:3001/mcp`    |
| `MCP_SERVER_TOKEN`                           | Optional; sent as `Authorization: Bearer <token>`    |
| `GEMINI_API_KEY`                             | Required for the assistant (Google AI Studio key)    |
| `GEMINI_MODEL`                               | Optional, default `gemini-3.5-flash`                 |

Start the server first (from `../backlog-games-mcp-server`), using the same token:

```bash
MCP_AUTH_TOKEN=change-me bin/rails s -p 3001
```

and set `MCP_SERVER_TOKEN=change-me` here. Without a token configured on the server,
development accepts unauthenticated requests; production rejects them.

## Tests

```bash
bin/rails db:test:prepare test
```

Controller tests replace `BacklogMcpClient.default` with `FakeMcpClient` and
`GeminiClient.default` with a scripted `FakeGemini`
(`test/test_helpers/fake_mcp_client.rb`), so they need neither the server nor a Gemini key.
`test/services/backlog_mcp_client_test.rb` covers the tool calls and error mapping.

Also: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`.
