{
  lib,
  config,
  pkgs,
  ...
}: let
  cfgDev = config.features.dev.enable or false;
  sqliteDbPath = "${config.xdg.dataHome}/mcp/sqlite/mcp.db";
  telegramSessionPath = "${config.xdg.dataHome}/mcp/telegram/session.json";
  gmailStateDir = "${config.home.homeDirectory}/.auto-gmail";
  meetingNotesDir = "${config.home.homeDirectory}/.claude/session-notes";
  chromiumProfileDir = "${config.xdg.dataHome}/mcp/chromium/profile";
  playwrightProfileDir = "${config.xdg.dataHome}/mcp/playwright/profile";
  playwrightOutputDir = "${config.xdg.dataHome}/mcp/playwright/output";
  playwrightBrowsersPath = "${config.xdg.cacheHome}/ms-playwright";
  docDir = lib.attrByPath ["xdg" "userDirs" "documents"] "${config.home.homeDirectory}/doc" config;
  picturesDir = lib.attrByPath ["xdg" "userDirs" "pictures"] "${config.home.homeDirectory}/pic" config;
  mediaSearchPathsList = lib.unique (lib.filter (path: path != null && path != "") [
    docDir
    "${config.home.homeDirectory}/notes"
    "${config.xdg.dataHome}/obsidian"
    "${config.xdg.dataHome}/screenshots"
    "${picturesDir}/shots"
    "${picturesDir}/Screenshots"
  ]);
  mediaSearchPathsString =
    if mediaSearchPathsList == []
    then docDir
    else lib.concatStringsSep ":" mediaSearchPathsList;
  mediaSearchCacheDir = "${config.xdg.cacheHome}/mcp/media-search";
  agendaIcsPathsList = lib.unique (lib.filter (path: path != null && path != "") [
    "${config.xdg.configHome}/vdirsyncer/calendars"
    "${config.xdg.dataHome}/calendars"
    "${config.home.homeDirectory}/.local/share/calendars"
  ]);
  agendaIcsPathsString =
    if agendaIcsPathsList == []
    then "${config.xdg.configHome}/vdirsyncer/calendars"
    else lib.concatStringsSep ":" agendaIcsPathsList;
  agendaNotesFile = "${config.xdg.dataHome}/mcp/agenda/notes.json";
  agendaNotesDir = builtins.dirOf agendaNotesFile;
  agendaLookaheadDays = 7;
  knowledgePathsList = lib.unique (mediaSearchPathsList
    ++ [
      "${config.home.homeDirectory}/code"
      "${config.home.homeDirectory}/projects"
      "${config.home.homeDirectory}/workspace"
    ]);
  knowledgePathsString =
    if knowledgePathsList == []
    then docDir
    else lib.concatStringsSep ":" knowledgePathsList;
  knowledgeCacheDir = "${config.xdg.cacheHome}/mcp/knowledge";
  hmRepoRoot = "${config.neg.hmConfigRoot}";
  openAiKeyEnv = builtins.getEnv "OPENAI_API_KEY";
  teiEndpointEnv = builtins.getEnv "TEI_ENDPOINT";
  embeddingsProviderEnv = builtins.getEnv "EMBEDDINGS_PROVIDER";
  hasEnv = name: builtins.getEnv name != "";
  hasAllEnv = names: lib.all hasEnv names;
  context7Enabled = hasEnv "CONTEXT7_API_KEY";
  gmailEnabled = hasAllEnv ["GMAIL_CLIENT_ID" "GMAIL_CLIENT_SECRET" "GMAIL_REFRESH_TOKEN"] && hasEnv "OPENAI_API_KEY";
  gcalEnabled = hasAllEnv ["GCAL_CLIENT_ID" "GCAL_CLIENT_SECRET" "GCAL_REFRESH_TOKEN"];
  imapEnabled = hasAllEnv ["IMAP_HOST" "IMAP_PORT" "IMAP_USERNAME" "IMAP_PASSWORD"];
  smtpEnabled = hasAllEnv ["SMTP_HOST" "SMTP_PORT" "SMTP_USERNAME" "SMTP_PASSWORD" "SMTP_FROM_ADDRESS"];
  firecrawlEnabled = hasEnv "FIRECRAWL_API_KEY";
  elasticAuthProvided = hasEnv "ES_API_KEY" || hasAllEnv ["ES_USERNAME" "ES_PASSWORD"];
  elasticsearchEnabled = hasEnv "ES_URL" && elasticAuthProvided;
  sentryEnabled = hasEnv "SENTRY_TOKEN";
  slackEnabled = hasEnv "SLACK_BOT_TOKEN";
  githubEnabled = hasEnv "GITHUB_TOKEN";
  gitlabEnabled = hasEnv "GITLAB_TOKEN";
  discordEnabled = hasEnv "DISCORD_BOT_TOKEN";
  telegramEnabled = hasAllEnv ["TG_APP_ID" "TG_API_HASH"];
  disabledServers = [
    "browserbase"
    "brave-search"
    "docsearch-local"
    "exa"
    "exa-search"
    "git-local"
    "postgres-local"
    "redis-local"
  ];
in
  lib.mkIf cfgDev (lib.mkMerge [
    # Central MCP servers config written to $XDG_CONFIG_HOME/mcp/mcp.json
    {
      programs.mcp = let
        repoRoot = hmRepoRoot;
        fsBinary = "${pkgs.neg.mcp_server_filesystem}/bin/mcp-server-filesystem";
        rgBinary = "${pkgs.neg.mcp_ripgrep}/bin/mcp-ripgrep";
        memoryBinary = "${pkgs.neg.mcp_server_memory}/bin/mcp-server-memory";
        fetchBinary = "${pkgs.neg.mcp_server_fetch}/bin/mcp-server-fetch";
        seqBinary = "${pkgs.neg.mcp_server_sequential_thinking}/bin/mcp-server-sequential-thinking";
        timeBinary = "${pkgs.neg.mcp_server_time}/bin/mcp-server-time";
        gmailBinary = "${pkgs.neg.gmail_mcp}/bin/gmail-mcp-server";
        gcalBinary = "${pkgs.neg.gcal_mcp}/bin/gcal-mcp";
        imapBinary = "${pkgs.neg.imap_mcp}/bin/imap-mcp";
        smtpBinary = "${pkgs.neg.smtp_mcp}/bin/smtp-mcp";
        firecrawlBinary = "${pkgs.neg.firecrawl_mcp}/bin/firecrawl-mcp";
        elasticBinary = "${pkgs.neg.elasticsearch_mcp}/bin/elasticsearch-core-mcp-server";
        sentryBinary = "${pkgs.neg.sentry_mcp}/bin/mcp-server-sentry";
        slackBinary = "${pkgs.neg.slack_mcp}/bin/mcp-server-slack";
        sqliteBinary = "${pkgs.neg.sqlite_mcp}/bin/mcp-server-sqlite";
        githubBinary = "${pkgs.neg.github_mcp}/bin/github-mcp-server";
        gitlabBinary = "${pkgs.neg.gitlab_mcp}/bin/gitlab-mcp";
        discordBinary = "${pkgs.neg.discord_mcp}/bin/discordmcp";
        mediaBinary = "${pkgs.neg.media_mcp}/bin/media-mcp";
        mediaSearchBinary = "${pkgs.neg.media_search_mcp}/bin/media-search-mcp";
        agendaBinary = "${pkgs.neg.agenda_mcp}/bin/agenda-mcp";
        knowledgeBinary = "${pkgs.neg.knowledge_mcp}/bin/knowledge-mcp";
        playwrightBinary = "${pkgs.neg.playwright_mcp}/bin/playwright-mcp";
        chromiumBinary = "${pkgs.neg.chromium_mcp}/bin/mcp-chromium-cdp";
        meetingNotesBinary = "${pkgs.neg.meeting_notes_mcp}/bin/meeting-notes-mcp";
        telegramBinary = "${pkgs.neg.telegram_mcp}/bin/telegram-mcp";
      in {
        enable = true;
        servers =
          lib.filterAttrs (name: _: !(lib.elem name disabledServers)) (
            {
            # Kitchen‑sink demo server with many tools; runs via npx
            everything = {
              command = "npx";
              args = [
                "-y"
                "@modelcontextprotocol/server-everything"
              ];
            };

            filesystem-local = {
              command = fsBinary;
              args = [repoRoot];
            };

            rg-index = {
              command = rgBinary;
              env = {MCP_RIPGREP_ROOT = repoRoot;};
            };

            memory-local = {
              command = memoryBinary;
            };

            fetch-http = {
              command = fetchBinary;
            };

            sequential-thinking = {
              command = seqBinary;
            };

            time-local = {
              command = timeBinary;
            };

            sqlite = {
              command = sqliteBinary;
              args = [
                "--db-path"
                sqliteDbPath
              ];
            };

            media-control = {
              command = mediaBinary;
              env = {
                MCP_MPD_HOST = config.media.audio.mpd.host;
                MCP_MPD_PORT = toString config.media.audio.mpd.port;
                PIPEWIRE_SINK = "@DEFAULT_AUDIO_SINK@";
                WPCTL_BIN = "${pkgs.wireplumber}/bin/wpctl";
              };
            };

            media-search = {
              command = mediaSearchBinary;
              env = {
                MCP_MEDIA_SEARCH_PATHS = mediaSearchPathsString;
                MCP_MEDIA_SEARCH_CACHE = mediaSearchCacheDir;
                MCP_MEDIA_OCR_LANG = "{env:MCP_MEDIA_OCR_LANG}";
                TESSERACT_BIN = "${pkgs.tesseract}/bin/tesseract";
              };
            };

            agenda = {
              command = agendaBinary;
              env = {
                MCP_AGENDA_ICS_PATHS = agendaIcsPathsString;
                MCP_AGENDA_NOTES_FILE = agendaNotesFile;
                MCP_AGENDA_LOOKAHEAD_DAYS = toString agendaLookaheadDays;
                MCP_AGENDA_TZ = "{env:MCP_AGENDA_TZ}";
              };
            };

            knowledge-vector = {
              command = knowledgeBinary;
              env = {
                MCP_KNOWLEDGE_PATHS = knowledgePathsString;
                MCP_KNOWLEDGE_CACHE = knowledgeCacheDir;
                MCP_KNOWLEDGE_MODEL = "{env:MCP_KNOWLEDGE_MODEL}";
                MCP_KNOWLEDGE_EXTRA_PATTERNS = "{env:MCP_KNOWLEDGE_EXTRA_PATTERNS}";
              };
            };

            playwright = {
              command = playwrightBinary;
              args = [
                "--user-data-dir"
                playwrightProfileDir
                "--output-dir"
                playwrightOutputDir
              ];
              env = {
                PLAYWRIGHT_BROWSERS_PATH = playwrightBrowsersPath;
                PLAYWRIGHT_HEADLESS = "{env:PLAYWRIGHT_HEADLESS}";
                PLAYWRIGHT_CAPS = "{env:PLAYWRIGHT_CAPS}";
              };
            };

            chromium = {
              command = chromiumBinary;
              env = {
                CHROMIUM_PATH = "{env:CHROMIUM_PATH}";
                CHROMIUM_USER_DATA_DIR = chromiumProfileDir;
              };
            };

            meeting-notes = {
              command = meetingNotesBinary;
              env = {
                CLAUDE_SESSION_NOTES_DIR = meetingNotesDir;
              };
            };
          }
          // lib.optionalAttrs context7Enabled {
            context7 = {
              url = "https://mcp.context7.com/mcp";
              headers = {CONTEXT7_API_KEY = "{env:CONTEXT7_API_KEY}";};
            };
          }
          // lib.optionalAttrs gmailEnabled {
            gmail = {
              command = gmailBinary;
              env = {
                GMAIL_CLIENT_ID = "{env:GMAIL_CLIENT_ID}";
                GMAIL_CLIENT_SECRET = "{env:GMAIL_CLIENT_SECRET}";
                GMAIL_REFRESH_TOKEN = "{env:GMAIL_REFRESH_TOKEN}";
                OPENAI_API_KEY = "{env:OPENAI_API_KEY}";
              };
            };
          }
          // lib.optionalAttrs gcalEnabled {
            google-calendar = {
              command = gcalBinary;
              env = {
                GCAL_CLIENT_ID = "{env:GCAL_CLIENT_ID}";
                GCAL_CLIENT_SECRET = "{env:GCAL_CLIENT_SECRET}";
                GCAL_REFRESH_TOKEN = "{env:GCAL_REFRESH_TOKEN}";
                GCAL_ACCESS_TOKEN = "{env:GCAL_ACCESS_TOKEN}";
                GCAL_CALENDAR_ID = "{env:GCAL_CALENDAR_ID}";
              };
            };
          }
          // lib.optionalAttrs imapEnabled {
            imap-mail = {
              command = imapBinary;
              env = {
                IMAP_HOST = "{env:IMAP_HOST}";
                IMAP_PORT = "{env:IMAP_PORT}";
                IMAP_USERNAME = "{env:IMAP_USERNAME}";
                IMAP_PASSWORD = "{env:IMAP_PASSWORD}";
                IMAP_USE_SSL = "{env:IMAP_USE_SSL}";
              };
            };
          }
          // lib.optionalAttrs smtpEnabled {
            smtp-mail = {
              command = smtpBinary;
              env = {
                SMTP_HOST = "{env:SMTP_HOST}";
                SMTP_PORT = "{env:SMTP_PORT}";
                SMTP_USERNAME = "{env:SMTP_USERNAME}";
                SMTP_PASSWORD = "{env:SMTP_PASSWORD}";
                SMTP_FROM_ADDRESS = "{env:SMTP_FROM_ADDRESS}";
                SMTP_USE_TLS = "{env:SMTP_USE_TLS}";
                SMTP_USE_SSL = "{env:SMTP_USE_SSL}";
                SMTP_BEARER_TOKEN = "{env:SMTP_BEARER_TOKEN}";
              };
            };
          }
          // lib.optionalAttrs firecrawlEnabled {
            firecrawl = {
              command = firecrawlBinary;
              env = {
                FIRECRAWL_API_KEY = "{env:FIRECRAWL_API_KEY}";
                FIRECRAWL_API_URL = "{env:FIRECRAWL_API_URL}";
              };
            };
          }
          // lib.optionalAttrs elasticsearchEnabled {
            elasticsearch = {
              command = elasticBinary;
              env = {
                ES_URL = "{env:ES_URL}";
                ES_API_KEY = "{env:ES_API_KEY}";
                ES_USERNAME = "{env:ES_USERNAME}";
                ES_PASSWORD = "{env:ES_PASSWORD}";
                ES_SSL_SKIP_VERIFY = "{env:ES_SSL_SKIP_VERIFY}";
              };
            };
          }
          // lib.optionalAttrs sentryEnabled {
            sentry = {
              command = sentryBinary;
              env = {
                SENTRY_TOKEN = "{env:SENTRY_TOKEN}";
              };
            };
          }
          // lib.optionalAttrs slackEnabled {
            slack = {
              command = slackBinary;
              env = {
                SLACK_BOT_TOKEN = "{env:SLACK_BOT_TOKEN}";
                SLACK_TEAM_ID = "{env:SLACK_TEAM_ID}";
                SLACK_CHANNEL_IDS = "{env:SLACK_CHANNEL_IDS}";
              };
            };
          }
          // lib.optionalAttrs githubEnabled {
            github = {
              command = githubBinary;
              args = ["stdio"];
              env = {
                GITHUB_PERSONAL_ACCESS_TOKEN = "{env:GITHUB_TOKEN}";
                GITHUB_HOST = "{env:GITHUB_HOST}";
                GITHUB_TOOLSETS = "{env:GITHUB_TOOLSETS}";
                GITHUB_DYNAMIC_TOOLSETS = "{env:GITHUB_DYNAMIC_TOOLSETS}";
                GITHUB_READ_ONLY = "{env:GITHUB_READ_ONLY}";
                GITHUB_LOCKDOWN_MODE = "{env:GITHUB_LOCKDOWN_MODE}";
              };
            };
          }
          // lib.optionalAttrs gitlabEnabled {
            gitlab = {
              command = gitlabBinary;
              env = {
                GITLAB_PERSONAL_ACCESS_TOKEN = "{env:GITLAB_TOKEN}";
                GITLAB_API_URL = "{env:GITLAB_API_URL}";
                GITLAB_PROJECT_ID = "{env:GITLAB_PROJECT_ID}";
                GITLAB_ALLOWED_PROJECT_IDS = "{env:GITLAB_ALLOWED_PROJECT_IDS}";
                GITLAB_READ_ONLY_MODE = "{env:GITLAB_READ_ONLY_MODE}";
                USE_GITLAB_WIKI = "{env:USE_GITLAB_WIKI}";
                USE_MILESTONE = "{env:USE_MILESTONE}";
                USE_PIPELINE = "{env:USE_PIPELINE}";
              };
            };
          }
          // lib.optionalAttrs discordEnabled {
            discord = {
              command = discordBinary;
              env = {
                DISCORD_TOKEN = "{env:DISCORD_BOT_TOKEN}";
                DISCORD_CHANNEL_IDS = "{env:DISCORD_CHANNEL_IDS}";
              };
            };
          }
          // lib.optionalAttrs telegramEnabled {
            telegram = {
              command = telegramBinary;
              env = {
                TG_APP_ID = "{env:TG_APP_ID}";
                TG_API_HASH = "{env:TG_API_HASH}";
                TG_SESSION_PATH = telegramSessionPath;
              };
            };
          }
          );
      };

      home.packages =
        [
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
        ]
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

      home.activation.ensureMcpStateDirs = config.lib.neg.mkEnsureRealDirsMany (
        [
          (builtins.dirOf sqliteDbPath)
          (builtins.dirOf telegramSessionPath)
          gmailStateDir
          meetingNotesDir
          chromiumProfileDir
          playwrightProfileDir
          playwrightOutputDir
          playwrightBrowsersPath
          mediaSearchCacheDir
          agendaNotesDir
          knowledgeCacheDir
        ]
      );
    }

    # Optional integrations: OpenCode and VS Code consume the central MCP list
    {
      programs.opencode = {
        enable = true;
        enableMcpIntegration = true;
        # Keep default package (pkgs.opencode) if available; do not force extra settings
      };
      # VSCode MCP integration can be enabled later if needed;
      # it may introduce extra evaluation edges in some environments.
      # programs.vscode.profiles.default.enableMcpIntegration = true;
    }
    (lib.mkIf (config.programs.claude-code.enable or false) {
      # Claude Desktop expects the same MCP list; reuse the generated servers.
      programs.claude-code.mcpServers = config.programs.mcp.servers;
    })
  ])
