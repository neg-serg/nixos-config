{
  lib,
  config,
  pkgs,
  negLib,
  ...
}:
with rec {
  db = negLib.web.defaultBrowser or {};
  browserRec = {
    bin = db.bin or "${lib.getExe' pkgs.xdg-utils "xdg-open"}";
    desktop = db.desktop or "floorp.desktop";
  };
  nvfPackage = config.programs.nvf.finalPackage or null;
  editorCmd =
    if (config.programs.nvf.enable or false) && nvfPackage != null
    then lib.getExe' nvfPackage "nvim"
    else lib.getExe' pkgs.neovim "nvim";
  defaultApplications = {
    terminal = {
      cmd = "${lib.getExe' pkgs.kitty "kitty"}";
      desktop = "kitty";
    };
    browser = {
      cmd = browserRec.bin;
      # Historically we kept just the desktop ID without suffix here.
      # Derive it from the full desktop file name.
      desktop = lib.removeSuffix ".desktop" browserRec.desktop;
    };
    editor = {
      cmd = "${editorCmd}";
      desktop = "nvim";
    };
  };

  browser = browserRec.desktop;
  pdfreader = "org.pwmt.zathura.desktop";
  telegram = "org.telegram.desktop.desktop";
  # Transmission 4 desktop ID (explicit to avoid legacy alias)
  torrent = "org.transmissionbt.Transmission.desktop";
  video = "mpv.desktop";
  image = "swayimg.desktop";
  editor = "${defaultApplications.editor.desktop}.desktop";

  # Minimal associations to keep noise low; handlr covers the rest
  my_associations =
    {
      # --- Browsing ---
      "text/html" = browser;
      "application/xhtml+xml" = browser;
      "x-scheme-handler/http" = browser;
      "x-scheme-handler/https" = browser;
      "x-scheme-handler/about" = browser;
      "x-scheme-handler/unknown" = browser;

      # --- Media ---
      "audio/*" = video;
      "video/*" = video;
      "image/*" = image;
      "image/svg+xml" = image;

      # --- Documents ---
      "application/pdf" = pdfreader;
      "application/epub+zip" = pdfreader;
      "image/vnd.djvu" = pdfreader;
      "application/postscript" = pdfreader;
      "application/vnd.comicbook+zip" = pdfreader;
      "application/vnd.comicbook+rar" = pdfreader;
      "application/x-cbz" = pdfreader;
      "application/x-cbr" = pdfreader;

      # --- Directories ---
      "inode/directory" = "kitty-open.desktop";

      # --- Playlists ---
      "audio/x-mpegurl" = video;
      "application/vnd.apple.mpegurl" = video;
      "application/x-scpls" = video;

      # --- Misc ---
      "x-scheme-handler/tg" = telegram;

      # --- Archives ---
      "application/zip" = editor;
      "application/x-tar" = editor;
      "application/gzip" = editor;
      "application/x-bzip2" = editor;
      "application/x-7z-compressed" = editor;
      "application/x-rar" = editor;
      "application/x-xz" = editor;

      # --- Editing (Text/Code/Config) ---
      "text/plain" = editor;
      "text/markdown" = editor;
      "text/x-markdown" = editor;
      "text/x-readme" = editor;
      "text/x-log" = editor;
      "text/x-tex" = editor;
      "text/x-diff" = editor;
      "text/x-patch" = editor;

      # Config & Data
      "application/json" = editor;
      "application/x-shellscript" = editor;
      "application/toml" = editor;
      "application/yaml" = editor;
      "text/x-yaml" = editor;
      "application/xml" = editor;
      "text/xml" = editor;
      "text/x-ini" = editor;
      "text/x-config" = editor;
      "text/csv" = editor;
      "text/x-csv" = editor;

      # Programming Languages
      "text/x-c" = editor;
      "text/x-c++" = editor;
      "text/x-python" = editor;
      "application/x-python" = editor;
      "text/x-php" = editor;
      "application/x-php" = editor;
      "text/x-rust" = editor;
      "text/rust" = editor;
      "text/x-go" = editor;
      "text/x-java" = editor;
      "text/x-lua" = editor;
      "text/x-nix" = editor;
      "text/x-script.python" = editor;
      "text/x-script.perl" = editor;
      "text/x-perl" = editor;
      "text/x-ruby" = editor;
      "text/x-makefile" = editor;
      "text/x-dockerfile" = editor;
      "text/x-cmake" = editor;
      "text/css" = editor;
      "application/javascript" = editor;
      "application/typescript" = editor;
      "text/x-sql" = editor;
      "application/sql" = editor;
    }
    // lib.optionalAttrs config.features.torrent.enable {
      "x-scheme-handler/magnet" = torrent;
    };
}; {
  home = {
    # Replace ad-hoc ensure/clean steps with lib.neg helpers
    # Ensure common runtime/config dirs exist as real directories
    activation.ensureCommonDirs = negLib.mkEnsureRealDirsMany [
      "${config.xdg.configHome}/mpv"
      "${config.xdg.stateHome}/zsh"
      "${config.home.homeDirectory}/.local/bin"
    ];

    # Ensure Gmail Maildir tree exists (INBOX, Sent, Drafts, All Mail)
    activation.ensureGmailMaildirs = negLib.mkEnsureMaildirs "${config.home.homeDirectory}/.local/mail/gmail" [
      "INBOX"
      "[Gmail]/Sent Mail"
      "[Gmail]/Drafts"
      "[Gmail]/All Mail"
    ];
  };

  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;
      desktop = "${config.home.homeDirectory}/.local/desktop";
      documents = "${config.home.homeDirectory}/doc";
      download = "${config.home.homeDirectory}/dw";
      music = "${config.home.homeDirectory}/music";
      pictures = "${config.home.homeDirectory}/pic";
      publicShare = "${config.home.homeDirectory}/.local/public";
      templates = "${config.home.homeDirectory}/.local/templates";
      videos = "${config.home.homeDirectory}/vid";
    };
    mime.enable = true;
    mimeApps = lib.mkMerge [
      {
        enable = true;
      }
      (lib.mkIf config.features.web.enable {
        associations.added = my_associations;
        defaultApplications = my_associations;
      })
    ];
  };
}
