{
  pkgs,
  lib,
  neg,
  config,
  ...
}:
let
  # Browser/App Definitions
  # No browser installed; MIME associations use xdg-open fallback
  browser = "xdg-open.desktop";
  pdfreader = "sioyek.desktop";
  telegram = "org.telegram.desktop.desktop";
  torrent = "org.transmissionbt.Transmission.desktop";
  video = "mpv.desktop";
  image = "swayimg.desktop;mpv.desktop";
  editor = "nvim.desktop";
  wordprocessor = "ai.storyteller.wordcraft.desktop";

  associations = {
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
    # Word/ODF/RTF documents go to WordCraft (the office suite on this host;
    # LibreOffice is not installed). Plain/markdown/tex/html stay with the editor.
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = wordprocessor;
    "application/vnd.openxmlformats-officedocument.wordprocessingml.template" = wordprocessor;
    "application/vnd.ms-word.document.macroEnabled.12" = wordprocessor;
    "application/vnd.ms-word.template.macroEnabled.12" = wordprocessor;
    "application/msword" = wordprocessor;
    "application/msword-template" = wordprocessor;
    "application/vnd.oasis.opendocument.text" = wordprocessor;
    "application/rtf" = wordprocessor;
    "text/rtf" = wordprocessor;
    "application/epub+zip" = pdfreader;
    "image/vnd.djvu" = pdfreader;
    "application/postscript" = pdfreader;
    "application/vnd.comicbook+zip" = pdfreader;
    "application/vnd.comicbook+rar" = pdfreader;
    "application/x-cbz" = pdfreader;
    "application/x-cbr" = pdfreader;

    # --- Directories ---
    "inode/directory" = "yazi.desktop";

    # --- Playlists ---
    "audio/x-mpegurl" = video;
    "application/vnd.apple.mpegurl" = video;
    "application/x-scpls" = video;

    # --- Misc ---
    "x-scheme-handler/tg" = telegram;
    "x-scheme-handler/magnet" = torrent;
    "x-scheme-handler/irori" = "irori.desktop";

    # --- Archives ---
    "application/zip" = editor;
    "application/x-tar" = editor;
    "application/gzip" = editor;
    "application/x-bzip2" = editor;
    "application/x-7z-compressed" = editor;
    "application/x-rar" = editor;
    "application/x-xz" = editor;

    # --- Editing (Text/Code) ---
    "text/plain" = editor;
    "text/markdown" = editor;
    "text/x-markdown" = editor;
    "text/x-readme" = editor;
    "text/x-log" = editor;
    "text/x-tex" = editor;
    "text/x-diff" = editor;
    "text/x-patch" = editor;
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
  };

  mimeAppsList = lib.generators.toINI { } {
    "Default Applications" = associations;
    "Added Associations" = associations;
  };

  # User Dirs
  userDirs = ''
    XDG_DESKTOP_DIR="$HOME/.local/desktop"
    XDG_DOCUMENTS_DIR="$HOME/doc"
    XDG_DOWNLOAD_DIR="$HOME/dw"
    XDG_MUSIC_DIR="$HOME/music"
    XDG_PICTURES_DIR="$HOME/pic"
    XDG_PUBLICSHARE_DIR="$HOME/.local/public"
    XDG_TEMPLATES_DIR="$HOME/.local/templates"
    XDG_VIDEOS_DIR="$HOME/vid"
  '';

  # Desktop entries that give a window its icon.
  #
  # A launcher or a window switcher finds an application's icon by matching the
  # window class to a desktop entry: vicinae's Switch Windows view
  # (`vicinae://launch/wm/switch-windows`, M1+g / Alt+Tab) matches the class
  # against every entry's `StartupWMClass` and then its id
  # (src/server/src/builtins/wm/switch-windows-view-host.cpp), and paints a
  # generic icon when nothing matches. `kitty.desktop` cannot answer for a kitty
  # started with `--class`, so the `term` and `nwim` windows and the teardown pad
  # (`--class teardown`, btop inside) need an entry of their own, named after the
  # class. `NoDisplay` keeps them out of the application lists; `Exec` repeats the
  # command the Hyprland binds launch (files/gui/hypr/hyprland.lua), so activating
  # an entry from a picker does what the key does.
  windowClassApps = {
    term = {
      name = "Terminal";
      comment = "kitty on the term workspace";
      exec = "kitty --class term";
      icon = "kitty";
    };
    nwim = {
      name = "Neovim";
      comment = "Neovim in kitty (the v wrapper)";
      exec = "kitty --class nwim -e ${config.lib.neg.homeDir}/.local/bin/v";
      icon = "nvim";
    };
    teardown = {
      name = "btop";
      comment = "System monitor and the live kernel log (the teardown pad)";
      exec = "kitty-glass --class teardown --session ${config.lib.neg.homeDir}/.config/kitty/teardown.session";
      icon = "btop";
    };
  };

  windowClassFiles = lib.mapAttrs' (
    class: app:
    lib.nameValuePair ".local/share/applications/${class}.desktop" {
      text = ''
        [Desktop Entry]
        Type=Application
        Name=${app.name}
        Comment=${app.comment}
        Exec=${app.exec}
        Icon=${app.icon}
        Terminal=false
        NoDisplay=true
        StartupWMClass=${class}
      '';
    }
  ) windowClassApps;
in
{
  config = lib.mkMerge [
    {
      # Activation: Create Directories
      systemd.user.services.xdg-user-dirs-create = {
        description = "Create XDG User Directories";
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = toString (
            pkgs.writeShellScript "create-xdg-dirs" ''
              mkdir -p \
                $HOME/.local/desktop \
                $HOME/doc \
                $HOME/dw \
                $HOME/music \
                $HOME/pic \
                $HOME/.local/public \
                $HOME/.local/templates \
                $HOME/vid \
                $HOME/.local/bin \
                $HOME/.local/mail/gmail/INBOX
            ''
          );
        };
      };
    }
    (neg.mkHomeFiles (
      {
        ".config/mimeapps.list".text = mimeAppsList;
        ".config/user-dirs.dirs".text = userDirs;

        ".local/share/applications/yazi.desktop".text = ''
          [Desktop Entry]
          Type=Application
          Name=Yazi
          GenericName=File Manager
          Comment=Terminal file manager (opens in kitty)
          Exec=kitty yazi %f
          Icon=system-file-manager
          Terminal=false
          Categories=System;FileManager;
          MimeType=inode/directory;
          Keywords=files;folders;manager;
        '';
      }
      // windowClassFiles
    ))
  ];
}
