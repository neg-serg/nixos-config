{ pkgs, ... }:
{
  adguardian-term = pkgs.adguardian;
  richcolors = pkgs.neg.richcolors;
  hxtools = pkgs.hxtools; # Collection of small tools over the years by j.eng
  ls-iommu = pkgs.neg.ls_iommu;
  skbtrace = pkgs.neg.skbtrace;

  # beatprints = pkgs.beatprints; # Disabled: upstream pylette tests fail
  webcamize = pkgs.neg.webcamize;
  rtcqs = pkgs.neg.rtcqs;
  tewi = pkgs.neg.tewi;
  playscii = pkgs.neg.playscii;
  two_percent = pkgs.neg.two_percent;
  subsonic-tui = pkgs.subsonic-tui;
  rmpc = pkgs.rmpc; # TUI music player client for MPD with album art support vi...
  pyprland = pkgs.pyprland; # Hyperland plugin system
  pyprland_fixed = pkgs.pyprland_fixed;
  surfingkeys-pkg = pkgs.surfingkeys-pkg;

  # mcp-server-filesystem = pkgs.neg.mcp_server_filesystem;
  # mcp-ripgrep = pkgs.neg.mcp_ripgrep;
  # mcp-server-git = pkgs.neg.mcp_server_git;
  # mcp-server-memory = pkgs.neg.mcp_server_memory;
  # mcp-server-fetch = pkgs.neg.mcp_server_fetch;
  # mcp-server-sequential-thinking = pkgs.neg.mcp_server_sequential_thinking;
  # mcp-server-time = pkgs.neg.mcp_server_time;
  # firecrawl-mcp = pkgs.neg.firecrawl_mcp;
  # gmail-mcp = pkgs.neg.gmail_mcp;
  # gcal-mcp = pkgs.neg.gcal_mcp;
  # imap-mcp = pkgs.neg.imap_mcp;
  # smtp-mcp = pkgs.neg.smtp_mcp;
  # elasticsearch-mcp = pkgs.neg.elasticsearch_mcp;
  # sentry-mcp = pkgs.neg.sentry_mcp;
  # slack-mcp = pkgs.neg.slack_mcp;
  # sqlite-mcp = pkgs.neg.sqlite_mcp;
  # telegram-mcp = pkgs.neg.telegram_mcp;
  # github-mcp = pkgs.neg.github_mcp;
  # gitlab-mcp = pkgs.neg.gitlab_mcp;
  # discord-mcp = pkgs.neg.discord_mcp;
  # playwright-mcp = pkgs.neg.playwright_mcp;
  # chromium-mcp = pkgs.neg.chromium_mcp;
  # meeting-notes-mcp = pkgs.neg.meeting_notes_mcp;
  # media-mcp = pkgs.neg.media_mcp;
  # media-search-mcp = pkgs.neg.media_search_mcp;
  # agenda-mcp = pkgs.neg.agenda_mcp;
  # knowledge-mcp = pkgs.neg.knowledge_mcp;
  # brave-search-mcp = pkgs.neg.brave_search_mcp;
  # exa-mcp = pkgs.neg.exa_mcp;
  # postgres-mcp = pkgs.neg.postgres_mcp;
  # telegram-bot-mcp = pkgs.neg.telegram_bot_mcp;
  # tsgram-mcp = pkgs.neg.tsgram_mcp;
}
