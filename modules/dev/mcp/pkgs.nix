{
  lib,
  config,
  pkgs,
  ...
}: let
  devEnabled = config.features.dev.enable or false;
  hasEnv = name: builtins.getEnv name != "";
  hasAll = names: lib.all hasEnv names;
  gmailEnabled = hasAll ["GMAIL_CLIENT_ID" "GMAIL_CLIENT_SECRET" "GMAIL_REFRESH_TOKEN"] && hasEnv "OPENAI_API_KEY";
  gcalEnabled = hasAll ["GCAL_CLIENT_ID" "GCAL_CLIENT_SECRET" "GCAL_REFRESH_TOKEN"];
  imapEnabled = hasAll ["IMAP_HOST" "IMAP_PORT" "IMAP_USERNAME" "IMAP_PASSWORD"];
  smtpEnabled = hasAll ["SMTP_HOST" "SMTP_PORT" "SMTP_USERNAME" "SMTP_PASSWORD" "SMTP_FROM_ADDRESS"];
  firecrawlEnabled = hasEnv "FIRECRAWL_API_KEY";
  elasticAuthProvided = hasEnv "ES_API_KEY" || hasAll ["ES_USERNAME" "ES_PASSWORD"];
  elasticsearchEnabled = hasEnv "ES_URL" && elasticAuthProvided;
  sentryEnabled = hasEnv "SENTRY_TOKEN";
  slackEnabled = hasEnv "SLACK_BOT_TOKEN";
  githubEnabled = hasEnv "GITHUB_TOKEN";
  gitlabEnabled = hasEnv "GITLAB_TOKEN";
  discordEnabled = hasEnv "DISCORD_BOT_TOKEN";
  telegramEnabled = hasAll ["TG_APP_ID" "TG_API_HASH"];
  braveSearchEnabled = hasEnv "BRAVE_API_KEY";
  exaEnabled = hasEnv "EXA_API_KEY";
  postgresEnabled = hasEnv "MCP_POSTGRES_URL";
  telegramBotEnabled = hasEnv "TELEGRAM_BOT_TOKEN";
  tsgramEnabled = (hasEnv "TELEGRAM_BOT_TOKEN") && hasEnv "TSGRAM_AUTHORIZED_CHAT_ID";
  basePackages = [
    pkgs.neg.mcp_server_filesystem # expose repo tree to MCP clients safely
    pkgs.neg.mcp_ripgrep # remote ripgrep search endpoint for agents
    pkgs.neg.mcp_server_memory # ephemeral key/value store for LLM chains
    pkgs.neg.mcp_server_fetch # HTTP fetch proxy with policy enforcement
    pkgs.neg.mcp_server_sequential_thinking # meta-tool for CoT scaffolding
    pkgs.neg.mcp_server_time # time conversions/current time helper
    pkgs.neg.sqlite_mcp # structured SQLite query endpoint
    pkgs.neg.media_mcp # local media control (playerctl) bridge
    pkgs.neg.media_search_mcp # media catalog searcher (embeddings aware)
    pkgs.neg.agenda_mcp # calendar/agenda merge engine for LLMs
    pkgs.neg.knowledge_mcp # knowledge-base lookup server
    pkgs.neg.playwright_mcp # headless browser automation for agents
    pkgs.neg.chromium_mcp # prebuilt Chromium runner for Playwright MCP
    pkgs.neg.meeting_notes_mcp # sync Claude meeting notes for recall
  ];
  packages =
    basePackages
    ++ lib.optional gmailEnabled pkgs.neg.gmail_mcp # Gmail read/send MCP connector
    ++ lib.optional gcalEnabled pkgs.neg.gcal_mcp # Google Calendar query/update MCP
    ++ lib.optional imapEnabled pkgs.neg.imap_mcp # raw IMAP inbox access for LLMs
    ++ lib.optional smtpEnabled pkgs.neg.smtp_mcp # outbound SMTP sending helper
    ++ lib.optional firecrawlEnabled pkgs.neg.firecrawl_mcp # Firecrawl web scraping API bridge
    ++ lib.optional elasticsearchEnabled pkgs.neg.elasticsearch_mcp # ES query MCP with auth
    ++ lib.optional sentryEnabled pkgs.neg.sentry_mcp # pull Sentry issue/alert data
    ++ lib.optional slackEnabled pkgs.neg.slack_mcp # Slack workspace messaging MCP
    ++ lib.optional githubEnabled pkgs.neg.github_mcp # GitHub API helper for repos/PRs
    ++ lib.optional gitlabEnabled pkgs.neg.gitlab_mcp # GitLab counterpart to GitHub MCP
    ++ lib.optional discordEnabled pkgs.neg.discord_mcp # Discord bot interface for LLM agents
    ++ lib.optional telegramEnabled pkgs.neg.telegram_mcp # Telegram client API bridge
    ++ lib.optional braveSearchEnabled pkgs.neg.brave_search_mcp # Brave Search API wrapper
    ++ lib.optional exaEnabled pkgs.neg.exa_mcp # EXA semantic search API connector
    ++ lib.optional postgresEnabled pkgs.neg.postgres_mcp # Postgres query executor MCP
    ++ lib.optional telegramBotEnabled pkgs.neg.telegram_bot_mcp # Telegram Bot API command MCP
    ++ lib.optional tsgramEnabled pkgs.neg.tsgram_mcp # TSGram short-link relay for bots
    ;
in {
  config = lib.mkIf devEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
