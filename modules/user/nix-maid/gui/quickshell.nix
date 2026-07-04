{
  pkgs,
  lib,
  config,
  inputs,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;

  # Flavor: selects which quickshell config to deploy
  flavor = config.features.gui.quickshell.flavor or "default";
  isOctashell = flavor == "octashell";
  isSshell = flavor == "sshell";

  # Source path based on flavor
  quickshellSrc = if isSshell
    then "${inputs.sshell.packages.${pkgs.stdenv.hostPlatform.system}.default}/share/sshell"
    else if isOctashell
    then ../../../../files/octashell
    else ../../../../files/quickshell;

  # Feature flags check
  quickshellEnabled =
    config.features.gui.enable or false
    && config.features.gui.qt.enable or false
    && config.features.gui.quickshell.enable or false
    && !(config.features.devSpeed.enable or false);

  # Quickshell package from flake input
  qsPkg = pkgs.quickshell; # Flexbile QtQuick based desktop shell toolkit

  # Wrapper factory
  mkQuickshellWrapper = import (inputs.self + "/lib/quickshell-wrapper.nix") {
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
    ] ++ lib.optionals isOctashell [
      pkgs.brightnessctl # backlight control
      pkgs.cliphist # clipboard history
      pkgs.wl-clipboard # wl-copy for clipboard
      pkgs.uwsm # universal Wayland session manager
    ] ++ lib.optionals isSshell [
      pkgs.brightnessctl # backlight control
      pkgs.cliphist # clipboard history
      pkgs.playerctl # MPRIS media player control
      pkgs.wireplumber # audio control (wpctl)
      pkgs.networkmanager # nmcli for network
      pkgs.cava # audio visualizer
      pkgs.jq # JSON processor
      pkgs.matugen # Material You color generator
      pkgs.imagemagick # image processing
      pkgs.findutils # find command
      pkgs.bc # calculator for battery script
    ];
  };

  # Theme init: copy read-only theme dir to writable cache dir before quickshell starts.
  # The directory name differs between flavors: octashell uses "theme", default uses "Theme".
  # Not needed for sshell.
  quickshellThemeDir = if isOctashell then "theme" else "Theme";

  quickshellThemeInitScript = pkgs.writeShellScript "quickshell-theme-init" ''
    theme_dir="$HOME/.config/quickshell/${quickshellThemeDir}"
    cache_dir="$HOME/.cache/quickshell-theme"
    if [ -d "$theme_dir" ] && [ ! -w "$theme_dir" ]; then
      mkdir -p "$cache_dir"
      if [ -z "$(ls -A "$cache_dir" 2>/dev/null)" ]; then
        cp -rT "$theme_dir" "$cache_dir" 2>/dev/null || true
      fi
      rm -rf "$theme_dir"
      ln -sf "$cache_dir" "$theme_dir"
    fi
  '';
in
lib.mkIf quickshellEnabled (
  lib.mkMerge [
    {
      # Wrapped quickshell package
      environment.systemPackages = [
        quickshellWrapped # Wrapped Quickshell with dependencies and environment
      ] ++ lib.optionals isOctashell [
        pkgs.papirus-icon-theme # icon theme used by octashell
      ] ++ lib.optionals isSshell [
        pkgs.material-symbols # Material Symbols icon font used by sshell
      ];

      # Quickshell panel service
      systemd.user.services.quickshell = {
        enable = true;
        description = "Quickshell - QtQuick based shell for Wayland";
        documentation = [ "https://github.com/outfoxxed/quickshell" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session-pre.target" "pipewire.service" ];
        wants = [ "pipewire.service" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${lib.getExe quickshellWrapped} -p %h/.config/quickshell/shell.qml";
          Restart = "on-failure";
          RestartSec = 1;
        };
      };
    }

    (n.mkHomeFiles {
      ".config/quickshell".source = quickshellSrc;
    })
    (lib.mkIf (!isSshell) {
      systemd.user.services.quickshell-theme-init = {
        description = "Copy read-only Theme to writable cache dir before quickshell starts";
        after = [ "maid-activation.service" ];
        before = [ "quickshell.service" ];
        requiredBy = [ "quickshell.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${quickshellThemeInitScript}";
        };
      };

      systemd.user.services.quickshell.after = lib.mkForce [ "graphical-session-pre.target" "maid-activation.service" "pipewire.service" ];
      systemd.user.services.quickshell.wants = [ "maid-activation.service" ];
    })
  ]
)
