{
  lib,
  neg,
  pkgs,
  config,
  ...
}:
let
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };

  # The on-demand launcher registers a GC root here on first run
  # (lib/on-demand-app.nix), so desktop icons have to be addressed under $HOME.
  # Pointing `icon` at the package's store path instead would pull the app's
  # whole closure into system-path — the one thing the launcher avoids.
  appRoot = "/home/neg/.local/state/nix-apps";

  # Reads evdev through libinput, so it needs the user in `input`
  # (see modules/system/users.nix) and needs no X11/XWayland.
  showmethekey = onDemand {
    name = "showmethekey";
    attr = "showmethekey";
    binary = "showmethekey-gtk"; # GTK4 overlay; -cli only prints to stdout
  };

  # Flutter app whose main program is localsend_app; the launcher on PATH stays
  # `localsend`, matching the desktop entry below.
  localsend = onDemand {
    name = "localsend";
    attr = "localsend";
    binary = "localsend_app";
  };

  # Prebuilt Electron bundle repacked from the upstream AppImage.
  losslesscut = onDemand {
    name = "losslesscut";
    attr = "losslesscut-bin";
    binary = "losslesscut";
  };
in
{
  config = lib.mkMerge [
    {
      # Packages
      environment.systemPackages = [
        # Galaxy Buds manager — ANC/EQ/touchpad/battery over RFCOMM/SPP.
        # The buds are normally handed to the Questyle dongle; this app needs
        # them paired with the PC's own adapter (see modules/system/kernel for
        # CONFIG_BT_RFCOMM, which this app depends on).
        (onDemand {
          name = "GalaxyBudsClient";
          attr = "galaxy-buds-client";
        }) # unofficial Galaxy Buds manager (ANC/EQ/touchpad), on demand
        (pkgs.makeDesktopItem {
          name = "GalaxyBudsClient";
          desktopName = "Galaxy Buds Client";
          exec = "GalaxyBudsClient";
          icon = "galaxy-buds-client";
          categories = [ "Settings" ];
        })
        # Chromium-family apps (Vivaldi) shell out to zenity/kdialog/xmessage
        # for the "profile is in use" dialog. With none of them installed the
        # dialog cannot be shown and the browser just exits silently on a stale
        # SingletonLock.
        pkgs.zenity # GTK dialog tool Chromium uses for profile-in-use prompts
        (onDemand {
          name = "hyprshell";
          attr = "hyprshell";
        }) # GTK4 window switcher + app launcher for Hyprland (ex-hyprswitch)
        # Hyprland dialogs (hyprland-dialog/-welcome/-run/...) on hyprtoolkit;
        # replaced hyprland-qtutils, which ships the same binary names.
        pkgs.hyprland-guiutils # Hyprland GUI utilities (hyprtoolkit, ex-hyprland-qtutils)

        # On-screen keystrokes for demos and screen recordings; the overlay
        # itself is click-through and toggled from its own window.
        showmethekey
        (pkgs.makeDesktopItem {
          name = "showmethekey";
          desktopName = "Show Me The Key";
          comment = "Show the keys you type on screen (works on Wayland via libinput)";
          exec = "showmethekey";
          icon = "${appRoot}/showmethekey/share/icons/hicolor/128x128/apps/one.alynx.showmethekey.png";
          categories = [ "Utility" ];
        })

        # AirDrop-style transfer to phones and other PCs. 53317/tcp+udp is
        # accepted from private ranges on every interface (files/net/firewall-extra.sh),
        # so receiving works on any LAN, not just net1.
        localsend
        (pkgs.makeDesktopItem {
          name = "localsend";
          desktopName = "LocalSend";
          genericName = "File Transfer";
          comment = "Send files to phones and other computers on the local network";
          exec = "localsend %U";
          icon = "${appRoot}/localsend/share/icons/hicolor/512x512/apps/localsend.png";
          categories = [
            "Network"
            "FileTransfer"
          ];
          startupWMClass = "org.localsend.localsend_app";
        })

        # Lossless video/audio trimming (ffmpeg stream copy, no re-encode).
        losslesscut
        (pkgs.makeDesktopItem {
          name = "losslesscut";
          desktopName = "LosslessCut";
          genericName = "Lossless video/audio cutter";
          comment = "Cut and merge video/audio without re-encoding";
          exec = "losslesscut %F";
          icon = "${appRoot}/losslesscut/share/icons/losslesscut.png";
          categories = [
            "AudioVideo"
            "Video"
          ];
          mimeTypes = [
            "video/mp4"
            "video/x-matroska"
            "video/webm"
            "audio/mpeg"
            "audio/flac"
          ];
        })
      ];

      # Receiving is handled by files/net/firewall-extra.sh rather than
      # programs.localsend: that module writes the *global* port lists, which
      # policy.nix clears with mkForce on this host, and it would open 53317 to
      # the whole internet instead of private sources only.
    }
    (neg.mkHomeFiles {
      # Handlr Config
      ".config/handlr/handlr.toml".text = ''
        enable_selector = false
        selector = "vicinae dmenu -p 'Open With: ❯>'"
      '';
    })
  ];
}
