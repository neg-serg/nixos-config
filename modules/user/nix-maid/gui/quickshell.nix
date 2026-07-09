{
  pkgs,
  lib,
  config,
  inputs,
  neg,
  ...
}:
let
  n = neg;

  # Flavor: selects which quickshell config to deploy
  flavor = config.features.gui.quickshell.flavor or "default";
  isOctashell = flavor == "octashell";
  isSshell = flavor == "sshell" && (config.features.gui.sshell.enable or false);

  # Package sshell from raw source (sshell input uses flake = false)
  sshellPkg = pkgs.stdenv.mkDerivation {
    name = "sshell";
    src = inputs.sshell;
    installPhase = ''
      mkdir -p $out/share/sshell
      cp -r . $out/share/sshell/
    '';
  };

  # Source path based on flavor
  quickshellSrc =
    if isSshell then
      "${sshellPkg}/share/sshell"
    else if isOctashell then
      ../../../../files/octashell
    else
      ../../../../files/quickshell;

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
    ]
    ++ lib.optionals isOctashell [
      pkgs.brightnessctl # backlight control
      pkgs.cliphist # clipboard history
      pkgs.wl-clipboard # wl-copy for clipboard
      pkgs.uwsm # universal Wayland session manager
    ]
    ++ lib.optionals isSshell [
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

  # Theme init: deploy Theme from source to writable ~/.config/quickshell directory.
  # The directory name differs between flavors: octashell uses "theme", default uses "Theme".
  # Not needed for sshell.
  quickshellThemeDir = if isOctashell then "theme" else "Theme";

  # Theme source path (resolved to Nix store at build time)
  quickshellThemeSrc = "${quickshellSrc}/${quickshellThemeDir}";

  quickshellThemeInitScript = pkgs.writeShellScript "quickshell-theme-init" ''
    theme_dir="$HOME/.config/quickshell/${quickshellThemeDir}"
    theme_src="${quickshellThemeSrc}"
    if [ ! -d "$theme_dir" ]; then
      mkdir -p "$theme_dir"
      cp -rT "$theme_src" "$theme_dir" 2>/dev/null || true
    fi
    # Ensure quickshell can write to theme files (Nix store sources are read-only)
    chmod -R u+w "$theme_dir" 2>/dev/null || true
  '';

  # Build individual nix-maid entries for source dir top-level contents,
  # excluding immutable paths (Theme, .github).  This makes ~/.config/quickshell
  # a real writable directory so that theme-init can create Theme/ as writable.
  quickshellSrcEntries =
    if isSshell then
      { } # sshell uses whole-directory deployment (no theme-init needed)
    else
      builtins.readDir quickshellSrc;

  quickshellSrcNames =
    if isSshell then
      [ ]
    else
      builtins.filter (name: name != "Theme" && name != "theme" && name != ".github") (
        builtins.attrNames quickshellSrcEntries
      );

  quickshellHomeFiles =
    if isSshell then
      { ".config/quickshell".source = quickshellSrc; }
    else
      builtins.listToAttrs (
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
      ]
      ++ lib.optionals isOctashell [
        pkgs.papirus-icon-theme # icon theme used by octashell
      ]
      ++ lib.optionals isSshell [
        pkgs.material-symbols # Material Symbols icon font used by sshell
      ];

      # Quickshell panel service
      systemd.user.services.quickshell = {
        enable = true;
        description = "Quickshell - QtQuick based shell for Wayland";
        documentation = [ "https://github.com/outfoxxed/quickshell" ];
        partOf = [ "graphical-session.target" ];
        after = [
          "graphical-session-pre.target"
          "pipewire.service"
        ];
        wants = [ "pipewire.service" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${lib.getExe quickshellWrapped} -p %h/.config/quickshell/shell.qml";
          Restart = "on-failure";
          RestartSec = 1;
        };
      };
    }

    (n.mkHomeFiles quickshellHomeFiles)
    {
      # Remove old whole-directory quickshell symlink before nix-maid
      # activation deploys individual entries.  Without this, systemd-tmpfiles
      # hits "unsafe path transition" when trying to create symlinks inside a
      # symlinked parent directory (systemd >=252).
      systemd.user.services.quickshell-cleanup-symlink = lib.mkIf (!isSshell) {
        description = "Remove old quickshell symlink before nix-maid activation";
        before = [ "maid-activation.service" ];
        wantedBy = [ "maid-activation.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "quickshell-cleanup-symlink" ''
            if [ -L "$HOME/.config/quickshell" ]; then
              rm "$HOME/.config/quickshell"
            fi
          '';
        };
      };
    }
    (lib.mkIf (!isSshell) {
      systemd.user.services.quickshell-theme-init = {
        description = "Deploy writable Theme directory before quickshell starts";
        after = [ "maid-activation.service" ];
        before = [ "quickshell.service" ];
        requiredBy = [ "quickshell.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${quickshellThemeInitScript}";
        };
      };

      systemd.user.services.quickshell.after = lib.mkForce [
        "graphical-session-pre.target"
        "maid-activation.service"
        "pipewire.service"
      ];
      systemd.user.services.quickshell.wants = [ "maid-activation.service" ];
    })
  ]
)
