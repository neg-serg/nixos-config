{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  # Source path
  quickshellSrc = config.lib.neg.path "files/quickshell";

  # Feature flags check
  quickshellEnabled =
    config.lib.neg.enabled "gui"
    && config.lib.neg.enabled "gui.qt"
    && config.lib.neg.enabled "gui.quickshell"
    && !(config.lib.neg.enabled "devSpeed");

  # Quickshell package from flake input
  qsPkg = pkgs.quickshell; # Flexbile QtQuick based desktop shell toolkit

  # Wrapper factory
  mkQuickshellWrapper = import (config.lib.neg.path "lib/quickshell-wrapper.nix") {
    inherit lib pkgs;
  };

  # Wrapped quickshell package
  quickshellWrapped = mkQuickshellWrapper {
    inherit qsPkg;
    extraPath = [
      pkgs.coreutils # basic file, shell and text manipulation utilities
      pkgs.bash # GNU Bourne-Again Shell
      pkgs.socat # multipurpose relay (SOcket CAT)
      pkgs.iproute2 # networking utilities
      pkgs.iputils # basic networking tool suite (ping, traceroute, etc.)
      pkgs.dash # POSIX-compliant shell
      pkgs.ffmpeg # multimedia framework
      pkgs.mpc # client for MPD
      pkgs.gawk # GNU awk: used by SystemMonitor probes parsing /proc/{meminfo,swaps,diskstats}
      pkgs.hyprland # dynamic tiling Wayland compositor
      pkgs.neg.rsmetrx # custom metrics exporter
      pkgs.khal # CLI calendar (used by CalendarEvents.js for khal list)
    ];
  };

  # Pre-start init: deploy writable config directories before quickshell starts.
  # Theme, Settings — copy-once so user edits persist.
  # Components, Bar — force-copied on every start so dev edits under
  # /etc/nixos/files/quickshell/ take effect immediately.
  quickshellPreStart = pkgs.writeShellScript "quickshell-pre-start" ''
    qs_dir="$HOME/.config/quickshell"
    src="${quickshellSrc}"

    # Self-heal nix-maid symlinks: during `nixos-rebuild switch` the cleanup
    # service deletes the static dir while quickshell can restart before
    # maid-activation recreates it. If shell.qml is gone, wait for activation.
    if [ ! -e "$qs_dir/shell.qml" ] && [ -d "$qs_dir" ]; then
      systemctl --user start --wait maid-activation.service 2>/dev/null || true
      # Fallback: run the activation script directly if the unit didn't help.
      if [ ! -e "$qs_dir/shell.qml" ]; then
        # Run ONLY the newest activation (ls -t): the glob matches every
        # generation in the store (dozens); iterating them in hash order
        # blows the 90s start-pre timeout and wedges the shell in a
        # restart loop.
        newest=$(ls -t /nix/store/*-all-maid/nix-maid-neg/bin/activate 2>/dev/null | head -1)
        [ -n "$newest" ] && [ -x "$newest" ] && "$newest"
      fi
    fi

    # Theme/ — copy-once from Nix store, make writable
    if [ ! -d "$qs_dir/Theme" ]; then
      mkdir -p "$qs_dir/Theme"
      cp -rT "$src/Theme" "$qs_dir/Theme" 2>/dev/null || true
      chmod -R u+w "$qs_dir/Theme" 2>/dev/null || true
    fi

    # Settings/ — force-copy on every start so repo changes (Theme.qml, Settings.qml)
    # propagate; dir stays writable for qs runtime state.
    mkdir -p "$qs_dir/Settings"
    cp -rfT "$src/Settings" "$qs_dir/Settings" 2>/dev/null || true
    chmod -R u+w "$qs_dir/Settings" 2>/dev/null || true

    # Settings.json — copy-once, user-editable
    if [ ! -f "$qs_dir/Settings.json" ]; then
      cp "$src/Settings.json" "$qs_dir/Settings.json" 2>/dev/null || true
      chmod u+w "$qs_dir/Settings.json" 2>/dev/null || true
    fi

    # Components/ — force-copy on every start for dev iteration
    mkdir -p "$qs_dir/Components"
    cp -rfT "$src/Components" "$qs_dir/Components" 2>/dev/null || true
    chmod -R u+w "$qs_dir/Components" 2>/dev/null || true

    # Bar/ — force-copy on every start for dev iteration
    mkdir -p "$qs_dir/Bar"
    cp -rfT "$src/Bar" "$qs_dir/Bar" 2>/dev/null || true
    chmod -R u+w "$qs_dir/Bar" 2>/dev/null || true

    # Helpers/ — force-copy on every start for dev iteration
    mkdir -p "$qs_dir/Helpers"
    cp -rfT "$src/Helpers" "$qs_dir/Helpers" 2>/dev/null || true
    chmod -R u+w "$qs_dir/Helpers" 2>/dev/null || true

    # Notifications/ — force-copy on every start for dev iteration
    mkdir -p "$qs_dir/Notifications"
    cp -rfT "$src/Notifications" "$qs_dir/Notifications" 2>/dev/null || true
    chmod -R u+w "$qs_dir/Notifications" 2>/dev/null || true

    # art/, shaders/ — force-copy on every start: the static symlink tree is
    # created by nix-maid activation AFTER the switch, so a shell started
    # meanwhile reads a half-deployed tree (missing 8.svg, wedge_clip.qsb →
    # startup warnings). Deterministic deployment, same pattern as above.
    mkdir -p "$qs_dir/art"
    cp -rfT "$src/art" "$qs_dir/art" 2>/dev/null || true
    chmod -R u+w "$qs_dir/art" 2>/dev/null || true

    mkdir -p "$qs_dir/shaders"
    cp -rfT "$src/shaders" "$qs_dir/shaders" 2>/dev/null || true
    chmod -R u+w "$qs_dir/shaders" 2>/dev/null || true
  '';
  # Build individual nix-maid entries for source dir top-level contents,
  # excluding writable paths (Theme, Settings, Settings.json, .github)
  # and force-copied paths (Components, Bar, Helpers, Notifications,
  # art, shaders).
  quickshellSrcEntries = builtins.readDir quickshellSrc;

  quickshellSrcNames = builtins.filter (
    name:
    name != "Theme"
    && name != "theme"
    && name != ".github"
    && name != "Settings.json"
    && name != "Settings"
    && name != "Components"
    && name != "Bar"
    && name != "Helpers"
    && name != "Notifications"
    && name != "art"
    && name != "shaders"
  ) (builtins.attrNames quickshellSrcEntries);

  quickshellHomeFiles = builtins.listToAttrs (
    map (name: {
      name = ".config/quickshell/${name}";
      value = {
        source = "${quickshellSrc}/${name}";
      };
    }) quickshellSrcNames
  );
in
lib.mkIf quickshellEnabled (
  lib.mkMerge [
    {
      # Wrapped quickshell package
      environment.systemPackages = [
        quickshellWrapped # Wrapped Quickshell with dependencies and environment
      ];

      # Quickshell panel service — ExecStartPre deploys writable config before start
      systemd.user.services.quickshell = {
        enable = true;
        description = "Quickshell - QtQuick based shell for Wayland";
        documentation = [ "https://github.com/outfoxxed/quickshell" ];
        partOf = [ "hyprland-session.target" ];
        after = [
          "graphical-session-pre.target"
          "pipewire.service"
        ];
        wants = [ "pipewire.service" ];
        wantedBy = [ "hyprland-session.target" ];
        serviceConfig = {
          ExecStartPre = "${quickshellPreStart}";
          ExecStart = "${lib.getExe quickshellWrapped} -p %h/.config/quickshell/shell.qml";
          Restart = "on-failure";
          RestartSec = 1;
          Environment = [
            "QML_XHR_ALLOW_FILE_WRITE=1"
            "PATH=/run/current-system/sw/bin:\${PATH}"
          ];
        };
      };
    }

    (neg.mkHomeFiles quickshellHomeFiles)
    {
      # Remove old quickshell symlinks before nix-maid activation deploys new ones.
      # Only deletes symlinks — preserves writable dirs (Theme, Settings)
      # and writable files (Settings.json) created by ExecStartPre.
      systemd.user.services.quickshell-cleanup-symlink = {
        description = "Remove old quickshell symlinks before nix-maid activation";
        before = [ "maid-activation.service" ];
        wantedBy = [ "maid-activation.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "quickshell-cleanup-symlink" ''
            qs="$HOME/.config/quickshell"
            if [ -L "$qs" ]; then
              rm -f "$qs" 2>/dev/null || true
            elif [ -d "$qs" ]; then
              find "$qs" -maxdepth 1 -type l -delete 2>/dev/null || true
            fi
            rm -rf "$HOME/.local/state/nix-maid/static/.config/quickshell" 2>/dev/null || true
          '';
        };
      };
    }
    {
      systemd.user.services.quickshell.after = lib.mkForce [
        "graphical-session-pre.target"
        "maid-activation.service"
        "pipewire.service"
      ];
      systemd.user.services.quickshell.wants = [ "maid-activation.service" ];
    }
  ]
)
