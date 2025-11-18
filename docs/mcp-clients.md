# MCP client inventory

`modules/dev/mcp.nix` writes the `programs.mcp.servers` attrset whenever `config.features.dev.enable = true`. The resulting MCP client list is the source of truth for the local command-and-control endpoints (`programs.opencode`, Claude Desktop, etc.) and is the list we reference for troubleshooting.

## Always-on servers
- `filesystem-local` — the filesystem-backed MCP server rooted at the home-manager dotfiles repository, used by most local searches.
- `rg-index` — `mcp-ripgrep` rooted at `config.neg.dotfilesRoot`, so the repo can be searched with ripgrep queries via MCP.
- `git-local` — exposes Git metadata from the same repository (currently failing at startup; see the section below).
- `memory-local` — the ephemeral `mcp-server-memory` store for short-lived context and historical entries.
- `fetch-http` — the `mcp-server-fetch` helper that allows MCP clients to make HTTP requests through the trusted stack.
- `sequential-thinking` — the sequential-thinking server used for structured problem-solving workflows.
- `time-local` — reports the current machine time/stats via `mcp-server-time`.
- `sqlite` — keeps the shared SQLite database at `$XDG_CONFIG_HOME/mcp/sqlite/mcp.db`.
- `media-control` — the `media_mcp` bridge to MPD/PIPEWIRE controls plus helpful wrappers from `modules/media`.
- `media-search` — `media_search_mcp` that indexes the configured media directories and optionally runs Tesseract for OCR.
- `agenda` — the ICS/notes merger that answers questions about calendars, reminders, and ad-hoc notes.
- `knowledge-vector` — the vector knowledge base over the documents specified in the config (`packages/mcp/knowledge`).
- `playwright` — launches Playwright with a persisted profile so MCP can drive browsers for workflows.
- `chromium` — a Chromium-backed automation entry point (`chromium_mcp`).
- `meeting-notes` — stores Claude meeting notes under `~/.claude/session-notes` for later reference.

## Environment-gated integrations
The following servers are enabled only when the corresponding environment variables are provided.
- `context7` — proxies requests to `https://mcp.context7.com/mcp`; set `CONTEXT7_API_KEY`.
- `gmail` — Gmail integration that requires all `GMAIL_*` secrets plus `OPENAI_API_KEY`.
- `google-calendar` — Google Calendar ingest that needs `GCAL_CLIENT_ID`, `GCAL_CLIENT_SECRET`, `GCAL_REFRESH_TOKEN`, and optionally calendar/collection overrides.
- `imap-mail` — generic IMAP inbox access; `IMAP_HOST`, `IMAP_PORT`, `IMAP_USERNAME`, `IMAP_PASSWORD`, and `IMAP_USE_SSL` gate it.
- `smtp-mail` — outbound SMTP support gated by the `SMTP_*` set that also includes bearer/token overrides.
- `firecrawl` — Firecrawl search API (`FIRECRAWL_API_KEY` plus optional `FIRECRAWL_API_URL`).
- `elasticsearch` — Elasticsearch proxy that reads `ES_URL`, credentials, and `ES_SSL_SKIP_VERIFY` if necessary.
- `sentry` — Sentry log lookup requiring `SENTRY_TOKEN`.
- `slack` — Slack assistant that needs `SLACK_BOT_TOKEN`, `SLACK_TEAM_ID`, and `SLACK_CHANNEL_IDS`.
- `brave-search` — Brave Search endpoint behind `BRAVE_API_KEY`.
- `browserbase` — BrowserBase search requiring `BROWSERBASE_API_KEY` (plus `STAGEHAND_API_KEY` for some flows).
- `exa-search` — EXA search results powered by `EXA_API_KEY`.
- `github` — GitHub MCP client that uses a PAT (`GITHUB_TOKEN`) and optional host/toolset overrides.
- `gitlab` — GitLab client requiring `GITLAB_TOKEN`, `GITLAB_API_URL`, and related project/mode flags.
- `redis-local` — connects to `REDIS_URL` for caching and scheduled information.
- `discord` — Discord scraper that uses `DISCORD_BOT_TOKEN` and channel IDs.
- `telegram` — Telegram client that writes its session to `$XDG_DATA_HOME/mcp/telegram/session.json` with `TG_APP_ID`/`TG_API_HASH`.
- `telegram-bot` — bot access using `TELEGRAM_BOT_TOKEN`.
- `docsearch-local` — local document search; `OPENAI_API_KEY` _or_ TEI-based `EMBEDDINGS_PROVIDER=tei`/`TEI_ENDPOINT` plus the other document-upload env vars are needed.
- `postgres-local` — PostgreSQL-backed MCP client that expects `POSTGRES_DSN` (and `POSTGRES_READ_ONLY` if applicable).

## Clients needing extra configuration right now
These MCP clients currently fail to start and therefore require additional setup before they can be relied on.
- `exa-search` — `MCP client for exa failed to start: No such file or directory (os error 2)`
- `redis-local` — `MCP client for redis-local failed to start: No such file or directory (os error 2)`
- `git-local` — `MCP client for git-local failed to start: handshaking with MCP server failed: connection closed: initialize response`
- `docsearch-local` — `MCP client for docsearch-local failed to start: No such file or directory (os error 2)`
- `browserbase` — `MCP client for browserbase failed to start: No such file or directory (os error 2)`
- `postgres-local` — `MCP client for postgres-local failed to start: handshaking with MCP server failed: connection closed: initialize response`
- `brave-search` — `MCP client for brave-search failed to start: No such file or directory (os error 2)`

The rest of the MCP clients listed above start up with the default configuration generated by `modules/dev/mcp.nix` and do not require additional manual wiring when `config.features.dev.enable` is true.

_Russian translation: see `docs/mcp-clients.ru.md`._
