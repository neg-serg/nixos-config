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
    pkgs.neg.mcp_server_filesystem
    pkgs.neg.mcp_ripgrep
    pkgs.neg.mcp_server_memory
    pkgs.neg.mcp_server_fetch
    pkgs.neg.mcp_server_sequential_thinking
    pkgs.neg.mcp_server_time
    pkgs.neg.sqlite_mcp
    pkgs.neg.media_mcp
    pkgs.neg.media_search_mcp
    pkgs.neg.agenda_mcp
    pkgs.neg.knowledge_mcp
    pkgs.neg.playwright_mcp
    pkgs.neg.chromium_mcp
    pkgs.neg.meeting_notes_mcp
  ];
  packages =
    basePackages
    ++ lib.optional gmailEnabled pkgs.neg.gmail_mcp
    ++ lib.optional gcalEnabled pkgs.neg.gcal_mcp
    ++ lib.optional imapEnabled pkgs.neg.imap_mcp
    ++ lib.optional smtpEnabled pkgs.neg.smtp_mcp
    ++ lib.optional firecrawlEnabled pkgs.neg.firecrawl_mcp
    ++ lib.optional elasticsearchEnabled pkgs.neg.elasticsearch_mcp
    ++ lib.optional sentryEnabled pkgs.neg.sentry_mcp
    ++ lib.optional slackEnabled pkgs.neg.slack_mcp
    ++ lib.optional githubEnabled pkgs.neg.github_mcp
    ++ lib.optional gitlabEnabled pkgs.neg.gitlab_mcp
    ++ lib.optional discordEnabled pkgs.neg.discord_mcp
    ++ lib.optional telegramEnabled pkgs.neg.telegram_mcp
    ++ lib.optional braveSearchEnabled pkgs.neg.brave_search_mcp
    ++ lib.optional exaEnabled pkgs.neg.exa_mcp
    ++ lib.optional postgresEnabled pkgs.neg.postgres_mcp
    ++ lib.optional telegramBotEnabled pkgs.neg.telegram_bot_mcp
    ++ lib.optional tsgramEnabled pkgs.neg.tsgram_mcp;
in {
  config = lib.mkIf devEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
