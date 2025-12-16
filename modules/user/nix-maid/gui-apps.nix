{pkgs, ...}: let
  # --- Vesktop (Discord) Config ---
  vesktopConfig = {
    settings = {
      notifyAboutUpdates = true;
      autoUpdate = false;
      autoUpdateNotification = true;
      useQuickCss = true;
      themeLinks = [
        "https://raw.githubusercontent.com/catppuccin/discord/main/themes/mocha.theme.css"
      ];
      enableReactDevtools = false;
      frameless = false;
      transparent = false;
      winCtrlQ = false;
      macosTranslucency = false;
      disableMinSize = false;
      winNativeTitleBar = false;
      plugins = {
        BadgeAPI = {enabled = true;};
        CommandsAPI = {enabled = true;};
        ContextMenuAPI = {enabled = true;};
        MemberListDecoratorsAPI = {enabled = false;};
        MessageAccessoriesAPI = {enabled = true;};
        MessageDecorationsAPI = {enabled = false;};
        MessageEventsAPI = {enabled = true;};
        MessagePopoverAPI = {enabled = false;};
        NoticesAPI = {enabled = true;};
        ServerListAPI = {enabled = false;};
        SettingsStoreAPI = {enabled = false;};
        NoTrack = {enabled = true;};
        Settings = {
          enabled = true;
          settingsLocation = "aboveActivity";
        };
        AlwaysAnimate = {enabled = false;};
        AlwaysTrust = {enabled = false;};
        AnonymiseFileNames = {
          enabled = true;
          method = 0;
          randomisedLength = 7;
        };
        BANger = {enabled = false;};
        BetterFolders = {
          enabled = false;
          sidebar = true;
          closeAllHomeButton = false;
          sidebarAnim = true;
          closeAllFolders = false;
          forceOpen = false;
        };
        BetterGifAltText = {enabled = true;};
        BetterNotesBox = {enabled = false;};
        BetterRoleDot = {enabled = false;};
        BetterUploadButton = {enabled = true;};
        BiggerStreamPreview = {enabled = true;};
        BlurNSFW = {enabled = false;};
        CallTimer = {enabled = true;};
        ClearURLs = {enabled = true;};
        ColorSighted = {enabled = false;};
        ConsoleShortcuts = {enabled = false;};
        CrashHandler = {enabled = true;};
        CustomRPC = {enabled = false;};
        DisableDMCallIdle = {enabled = false;};
        EmoteCloner = {enabled = true;};
        Experiments = {enabled = false;};
        F8Break = {enabled = false;};
        FakeNitro = {
          enabled = true;
          enableEmojiBypass = true;
          emojiSize = 48;
          transformEmojis = true;
          enableStickerBypass = true;
          stickerSize = 160;
          transformStickers = true;
          transformCompoundSentence = false;
          enableStreamQualityBypass = true;
        };
        FakeProfileThemes = {enabled = false;};
        FavoriteEmojiFirst = {enabled = false;};
        FixInbox = {enabled = false;};
        ForceOwnerCrown = {enabled = false;};
        FriendInvites = {enabled = false;};
        GameActivityToggle = {enabled = false;};
        GifPaste = {enabled = false;};
        HideAttachments = {enabled = false;};
        iLoveSpam = {enabled = false;};
        IgnoreActivities = {enabled = false;};
        ImageZoom = {enabled = false;};
        InvisibleChat = {enabled = false;};
        KeepCurrentChannel = {enabled = false;};
        LastFMRichPresence = {enabled = false;};
        LoadingQuotes = {enabled = false;};
        MemberCount = {enabled = true;};
        MessageClickActions = {enabled = false;};
        MessageLinkEmbeds = {enabled = true;};
        MessageLogger = {enabled = true;};
        MessageTags = {enabled = false;};
        MoreCommands = {enabled = false;};
        MoreKaomoji = {enabled = false;};
        MoreUserTags = {enabled = false;};
        Moyai = {enabled = false;};
        MuteNewGuild = {enabled = false;};
        MutualGroupDMs = {enabled = false;};
        NoBlockedMessages = {enabled = false;};
        NoDevtoolsWarning = {enabled = false;};
        NoF1 = {enabled = false;};
        NoPendingCount = {enabled = false;};
        NoProfileThemes = {enabled = false;};
        NoRPC = {enabled = false;};
        NoReplyMention = {enabled = false;};
        NoScreensharePreview = {enabled = false;};
        NoSystemBadge = {enabled = false;};
        NoUnblockToJump = {enabled = false;};
        NSFWGateBypass = {enabled = true;};
        oneko = {enabled = true;};
        "Party mode 🎉" = {enabled = false;};
        PermissionsViewer = {enabled = true;};
        petpet = {enabled = false;};
        PinDMs = {enabled = false;};
        PlainFolderIcon = {enabled = false;};
        PlatformIndicators = {enabled = false;};
        PronounDB = {enabled = false;};
        QuickMention = {enabled = false;};
        QuickReply = {enabled = false;};
        ReactErrorDecoder = {enabled = false;};
        ReadAllNotificationsButton = {enabled = false;};
        RelationshipNotifier = {enabled = true;};
        RevealAllSpoilers = {enabled = false;};
        ReverseImageSearch = {enabled = false;};
        ReviewDB = {enabled = false;};
        RoleColorEverywhere = {enabled = false;};
        SearchReply = {enabled = false;};
        SendTimestamps = {enabled = false;};
        ServerListIndicators = {enabled = false;};
        ShikiCodeblocks = {enabled = false;};
        ShowAllMessageButtons = {enabled = false;};
        ShowConnections = {enabled = false;};
        ShowHiddenChannels = {enabled = false;};
        ShowMeYourName = {
          enabled = true;
          mode = "nick-user";
          inReplies = false;
        };
        SilentMessageToggle = {enabled = false;};
        SilentTyping = {enabled = false;};
        SortFriendRequests = {enabled = false;};
        SpotifyControls = {enabled = false;};
        SpotifyCrack = {enabled = false;};
        SpotifyShareCommands = {enabled = false;};
        StartupTimings = {enabled = false;};
        SupportHelper = {enabled = true;};
        TextReplace = {enabled = false;};
        TimeBarAllActivities = {enabled = false;};
        Translate = {enabled = false;};
        TypingIndicator = {enabled = true;};
        TypingTweaks = {enabled = false;};
        Unindent = {enabled = true;};
        UnsuppressEmbeds = {enabled = false;};
        UrbanDictionary = {enabled = false;};
        UserVoiceShow = {enabled = false;};
        USRBG = {enabled = false;};
        UwUifier = {enabled = false;};
        ValidUser = {enabled = true;};
        VoiceChatDoubleClick = {enabled = true;};
        VcNarrator = {enabled = false;};
        VencordToolbox = {enabled = false;};
        ViewIcons = {enabled = true;};
        ViewRaw = {enabled = false;};
        VolumeBooster = {enabled = false;};
        GreetStickerPicker = {enabled = false;};
        WhoReacted = {enabled = false;};
        Wikisearch = {enabled = false;};
        "WebRichPresence (arRPC)" = {enabled = false;};
        WebContextMenus = {
          enabled = true;
          addBack = false;
        };
      };
      notifications = {
        timeout = 5000;
        position = "bottom-right";
        useNative = "not-focused";
        logLimit = 50;
      };
      cloud = {
        authenticated = false;
        url = "https://api.vencord.dev/";
        settingsSync = false;
        settingsSyncVersion = 1689448932291;
      };
    };
    quickCss = "";
  };

  # Rofi config source path
  rofiConfigSrc = ../../../packages/rofi-config;

  # Rofi wrapper script
  rofiWrapperScript = builtins.readFile ../../../files/rofi/rofi-wrapper.sh;
  rofiWrapper = pkgs.writeShellApplication {
    name = "rofi-wrapper";
    runtimeInputs = [
      pkgs.gawk # awk for simple text processing
      pkgs.gnused # sed for stream editing
      pkgs.jq # JSON processor
      pkgs.rofi # Rofi launcher
    ];
    text =
      builtins.replaceStrings
      ["@ROFI_BIN@" "@JQ_BIN@"]
      ["${pkgs.rofi}/bin/rofi" "${pkgs.jq}/bin/jq"]
      rofiWrapperScript;
  };

  # Rofi local bin wrapper
  rofiLocalBin = pkgs.writeShellScriptBin "rofi" ''
    #!/usr/bin/env bash
    set -euo pipefail
    exec ${rofiWrapper}/bin/rofi-wrapper "$@"
  '';
in {
  # Vesktop config - generate JSON file
  users.users.neg.maid.file.home = {
    ".config/vesktop/settings/settings.json".text = builtins.toJSON vesktopConfig;

    # Rofi config directory
    ".config/rofi".source = rofiConfigSrc;

    # Rofi themes in XDG data dir
    ".local/share/rofi/themes".source = rofiConfigSrc;

    # Handlr Config
    ".config/handlr/handlr.toml".text = ''
      enable_selector = false
      selector = "rofi -dmenu -p 'Open With: ❯>'"
    '';
  };

  # Systemd user services
  systemd.user.services = {
    # SwayOSD LibInput Backend
    swayosd-libinput-backend = {
      description = "SwayOSD LibInput Backend";
      after = ["graphical-session.target"];
      wantedBy = ["graphical-session.target"];
      serviceConfig = {
        ExecStart = "${pkgs.swayosd}/bin/swayosd-libinput-backend";
        Restart = "always";
      };
    };
  };

  # Packages
  environment.systemPackages = [
    pkgs.vesktop # Discord client with Vencord built-in
    pkgs.rofi # Application launcher for Wayland
    pkgs.swayosd # OSD for volume/brightness on Wayland
    rofiLocalBin # Rofi wrapper script
    pkgs.wallust # Color palette generator
  ];
}
