{
  pkgs,
  lib,
  config,
  neg,
  inputs,
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

  # Quickshell package from the pinned flake input (post-v0.3.0 crash fixes),
  # same source the greeter already uses; nixpkgs' v0.3.0 tag lacks them.
  qsPkg = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;

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
      # Bound the wait: during `nh os switch` the user systemd transaction is
      # held while the new generation activates, so an unbounded --wait can
      # stall past TimeoutStartSec (90s) and fail the whole switch with
      # "start-pre operation timed out". Fall through to the direct
      # activation-script fallback instead of hanging.
      ${pkgs.coreutils}/bin/timeout 25 systemctl --user start --wait maid-activation.service 2>/dev/null || true
      # Fallback: run the activation script directly if the unit didn't help.
      if [ ! -e "$qs_dir/shell.qml" ]; then
        # Run the SAME activation the unit would run (parsed from the unit
        # script). NOT `ls -t /nix/store/*-all-maid/...`: every store path
        # carries the epoch mtime, so ls -t picks a random generation and
        # can roll ~/.local/bin back to an old one (e.g. dropping the
        # glm-* scripts, breaking the Genelec wheel).
        unit_script=$(systemctl --user show maid-activation.service -p ExecStart --value 2>/dev/null | sed -n 's/.*path=\([^ ;]*\).*/\1/p')
        # The unit script resolves the correct activation path itself
        # (including $USER); run it directly as the fallback.
        [ -n "$unit_script" ] && [ -x "$unit_script" ] && "$unit_script"
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

    # Widgets/ — force-copy on every start. The nix-maid static tree exposes it
    # as a symlink without a qmldir, and Quickshell cannot load files from that
    # symlink ("File not found"/"No such file or directory" for
    # MusicPopup.qml/ScreenshotToast.qml). Copying to a real dir fixes loading.
    # Remove the stale nix-maid symlink first so the copy lands in a real dir.
    rm -rf "$qs_dir/Widgets"
    mkdir -p "$qs_dir/Widgets"
    cp -rfT "$src/Widgets" "$qs_dir/Widgets" 2>/dev/null || true
    cp -rT "$src/Widgets" "$qs_dir/Widgets" 2>/dev/null || true
    chmod -R u+w "$qs_dir/Widgets" 2>/dev/null || true

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
    && name != "Widgets"
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
        unitConfig = {
          StartLimitIntervalSec = 30;
          StartLimitBurst = 5;
        };
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
          # A startup crash (~1-3 s cycle) previously looped forever: the default
          # StartLimitBurst=5/10s never trips at this cadence (NRestarts hit 198).
          # Back off and stop after 5 quick failures in 30 s.
          RestartSec = 5;
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
