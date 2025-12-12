# Model Context Protocol (MCP) Servers

This configuration includes a comprehensive suite of MCP servers to empower AI agents with local system capabilities.

These servers are managed via **Home Manager** and configured in `modules/dev/mcp/pkgs.nix` and `home/modules/dev/mcp.nix`.

## Core Servers (Always Installed)

These servers are installed automatically when `features.dev.enable` is true.

| Server | Description | Binary |
| :--- | :--- | :--- |
| **mcp-ripgrep** | Fast recursive search in files (ripgrep) | `mcp-ripgrep` |
| **mcp-server-memory** | Persistent key-value memory store for AI agents | `mcp-server-memory` |
| **mcp-server-fetch** | HTTP client for fetching web content with policy enforcement | `mcp-server-fetch` |
| **mcp-server-sequential-thinking** | Tool for structured Chain-of-Thought (CoT) reasoning | `mcp-server-sequential-thinking` |
| **mcp-server-time** | Time and timezone conversion utilities | `mcp-server-time` |
| **sqlite-mcp** | Execute SQL queries on local SQLite databases | `mcp-server-sqlite` |
| **media-mcp** | Media playback control (MPD/Playerctl) | `media-mcp` |
| **media-search-mcp** | Semantic search in local media/books catalog | `media-search-mcp` |
| **agenda-mcp** | Aggregates calendars and tasks from multiple sources | `agenda-mcp` |
| **knowledge-mcp** | Knowledge base lookup (Obsidian, notes) | `knowledge-mcp` |
| **playwright-mcp** | Browser automation and testing | `playwright-mcp` |
| **chromium-mcp** | Chromium CDP bridge for Playwright | `mcp-chromium-cdp` |
| **meeting-notes-mcp** | Syncs and manages meeting notes | `meeting-notes-mcp` |

## Optional Servers (Environment Dependent)

These servers are installed and enabled **only** if specific environment variables are set (e.g., in `.env` or `~/.config/environment.d/`).

| Server | Triggers (Env Vars) | Description |
| :--- | :--- | :--- |
| **github-mcp** | `GITHUB_TOKEN` | GitHub API access (issues, PRs, repos) |
| **gitlab-mcp** | `GITLAB_TOKEN` | GitLab API access |
| **slack-mcp** | `SLACK_BOT_TOKEN` | Slack workspace interaction |
| **discord-mcp** | `DISCORD_BOT_TOKEN` | Discord bot integration |
| **telegram-mcp** | `TG_APP_ID`, `TG_API_HASH` | Telegram User API client |
| **telegram-bot-mcp** | `TELEGRAM_BOT_TOKEN` | Telegram Bot API |
| **postgres-mcp** | `MCP_POSTGRES_URL` | PostgreSQL database access |
| **firecrawl-mcp** | `FIRECRAWL_API_KEY` | Turn websites into LLM-ready markdown |
| **elasticsearch-mcp** | `ES_URL` (+Auth) | Elasticsearch query interface |
| **sentry-mcp** | `SENTRY_TOKEN` | Sentry error tracking and alerts |
| **gmail-mcp** | `GMAIL_CLIENT_ID`... | Read/Send emails via Gmail |
| **gcal-mcp** | `GCAL_CLIENT_ID`... | Manage Google Calendar events |
| **imap-mcp** | `IMAP_HOST`... | Generic IMAP email access |
| **smtp-mcp** | `SMTP_HOST`... | Generic SMTP email sending |

## Configuration

The MCP configuration file is automatically generated at:
`~/.config/mcp/mcp.json` (or defined location in XDG config).

This JSON file is consumed by compatible clients like **Claude Desktop**, **OpenCode**, or VS Code extensions.

### Managing Updates

Local MCP servers (like `awrit`, `vicinae`) can be updated using the helper script:

```bash
just update-npm
```

**Note:** Upstream servers (`packages/mcp/*`) are pinned in Nix and should be updated by bumping the package definitions manually to avoid build breakages.
