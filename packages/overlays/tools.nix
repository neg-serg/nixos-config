inputs: final: prev: let
  repoRoot = inputs.self;
  packagesRoot = repoRoot + "/packages";
  call = prev.callPackage;
in {
  neg = rec {
    # eBPF/BCC tools
    bpf_host_latency = call (packagesRoot + "/bpf-host-latency") {};
    "bpf-host-latency" = bpf_host_latency;
    # CLI/util packages
    a2ln = call (packagesRoot + "/a2ln") {};
    awrit = call (packagesRoot + "/awrit") {};
    bt_migrate = call (packagesRoot + "/bt-migrate") {};
    "bt-migrate" = bt_migrate;
    cxxmatrix = call (packagesRoot + "/cxxmatrix") {};
    comma = call (packagesRoot + "/comma") {};

    mcp_server_filesystem = call (packagesRoot + "/mcp/server-filesystem") {};
    "mcp-server-filesystem" = mcp_server_filesystem;

    mcp_ripgrep = call (packagesRoot + "/mcp/ripgrep") {};
    "mcp-ripgrep" = mcp_ripgrep;

    mcp_server_memory = call (packagesRoot + "/mcp/memory") {};
    "mcp-server-memory" = mcp_server_memory;

    mcp_server_fetch = call (packagesRoot + "/mcp/fetch") {};
    "mcp-server-fetch" = mcp_server_fetch;

    mcp_server_sequential_thinking = call (packagesRoot + "/mcp/sequentialthinking") {};
    "mcp-server-sequential-thinking" = mcp_server_sequential_thinking;

    mcp_server_time = call (packagesRoot + "/mcp/time") {};
    "mcp-server-time" = mcp_server_time;

    firecrawl_mcp = call (packagesRoot + "/mcp/firecrawl") {};
    "firecrawl-mcp" = firecrawl_mcp;

    gmail_mcp = call (packagesRoot + "/mcp/gmail") {};
    "gmail-mcp" = gmail_mcp;

    gcal_mcp = call (packagesRoot + "/mcp/gcal") {};
    "gcal-mcp" = gcal_mcp;

    imap_mcp = call (packagesRoot + "/mcp/imap") {};
    "imap-mcp" = imap_mcp;

    smtp_mcp = call (packagesRoot + "/mcp/smtp") {};
    "smtp-mcp" = smtp_mcp;

    elasticsearch_mcp = call (packagesRoot + "/mcp/elasticsearch") {};
    "elasticsearch-mcp" = elasticsearch_mcp;

    github_mcp = call (packagesRoot + "/mcp/github") {};
    "github-mcp" = github_mcp;

    gitlab_mcp = call (packagesRoot + "/mcp/gitlab") {};
    "gitlab-mcp" = gitlab_mcp;

    discord_mcp = call (packagesRoot + "/mcp/discord") {};
    "discord-mcp" = discord_mcp;

    playwright_mcp = call (packagesRoot + "/mcp/playwright") {};
    "playwright-mcp" = playwright_mcp;

    chromium_mcp = call (packagesRoot + "/mcp/chromium") {};
    "chromium-mcp" = chromium_mcp;

    meeting_notes_mcp = call (packagesRoot + "/mcp/meeting-notes") {};
    "meeting-notes-mcp" = meeting_notes_mcp;

    media_mcp = call (packagesRoot + "/mcp/media-control") {};
    "media-mcp" = media_mcp;

    media_search_mcp = call (packagesRoot + "/mcp/media-search") {};
    "media-search-mcp" = media_search_mcp;

    agenda_mcp = call (packagesRoot + "/mcp/agenda") {};
    "agenda-mcp" = agenda_mcp;

    knowledge_mcp = call (packagesRoot + "/mcp/knowledge") {};
    "knowledge-mcp" = knowledge_mcp;

    sentry_mcp = call (packagesRoot + "/mcp/sentry") {};
    "sentry-mcp" = sentry_mcp;

    slack_mcp = call (packagesRoot + "/mcp/slack") {};
    "slack-mcp" = slack_mcp;

    sqlite_mcp = call (packagesRoot + "/mcp/sqlite") {};
    "sqlite-mcp" = sqlite_mcp;

    telegram_mcp = call (packagesRoot + "/mcp/telegram") {};
    "telegram-mcp" = telegram_mcp;

    brave_search_mcp = call (packagesRoot + "/mcp/brave-search") {};
    "brave-search-mcp" = brave_search_mcp;

    exa_mcp = call (packagesRoot + "/mcp/exa") {};
    "exa-mcp" = exa_mcp;

    postgres_mcp = call (packagesRoot + "/mcp/postgres") {};
    "postgres-mcp" = postgres_mcp;

    telegram_bot_mcp = call (packagesRoot + "/mcp/telegram-bot") {};
    "telegram-bot-mcp" = telegram_bot_mcp;

    tsgram_mcp = call (packagesRoot + "/mcp/tsgram") {};
    "tsgram-mcp" = tsgram_mcp;

    # Music album metadata CLI (used by music-rename script)
    albumdetails = prev.stdenv.mkDerivation rec {
      pname = "albumdetails";
      version = "0.1";

      src = prev.fetchFromGitHub {
        owner = "neg-serg";
        repo = "albumdetails";
        rev = "91f4a546ccb42d82ae3b97462da73c284f05dbbe";
        hash = "sha256-9iaSyNqc/hXKc4iiDB6C7+2CMvKLWCRycsv6qVBD4wk=";
      };

      buildInputs = [prev.taglib];

      # Provide TagLib headers/libs to Makefile's LDLIBS
      preBuild = ''
        makeFlagsArray+=(LDLIBS="-I${prev.taglib}/include/taglib -L${prev.taglib}/lib -ltag_c")
      '';

      # Upstream Makefile supports PREFIX+DESTDIR, but copying is simpler here
      installPhase = ''
        mkdir -p "$out/bin"
        install -m755 albumdetails "$out/bin/albumdetails"
      '';

      meta = with prev.lib; {
        description = "Generate details for music album";
        homepage = "https://github.com/neg-serg/albumdetails";
        license = licenses.mit;
        platforms = platforms.unix;
        mainProgram = "albumdetails";
      };
    };

    # Pretty-printer library + CLI (ppinfo)
    pretty_printer = call (packagesRoot + "/pretty-printer") {};
    "pretty-printer" = pretty_printer;

    # Rofi plugins / desktop helpers
    rofi_games = call (packagesRoot + "/rofi-games") {};
    "rofi-games" = rofi_games;

    # Trader Workstation (IBKR) packaged from upstream installer
    tws = call (packagesRoot + "/tws") {};
  };
}
