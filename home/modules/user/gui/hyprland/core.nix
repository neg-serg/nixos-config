{
  lib,
  config,
  pkgs,
  xdg,
  hy3, # provided via mkHMArgs (wraps pkgs.hyprlandPlugins.hy3)
  raiseProvider ? null,
  systemdUser,
  ...
}:
with lib; let
  hyprWinList = pkgs.writeShellApplication {
    name = "hypr-win-list";
    runtimeInputs = [
      pkgs.python3
      pkgs.wl-clipboard
    ];
    text = let
      tpl = builtins.readFile ../hypr/hypr-win-list.py;
    in ''
                   exec python3 <<'PY'
      ${tpl}
      PY
    '';
  };
  coreFiles = [
    "vars.conf"
    "classes.conf"
    "rules.conf"
    # bindings.conf handled below (hy3/nohy3 variants)
    "autostart.conf"
  ];
  mkHyprSource = rel:
    xdg.mkXdgSource ("hypr/" + rel) {
      source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/user/gui/hypr/conf/${rel}";
      recursive = false;
      # Ensure repo-managed Hypr files replace any existing files
      force = true;
    };
  hy3Enabled = config.features.gui.hy3.enable or false;
  hyprsplitEnabled = config.features.gui.hyprsplit.enable or false;
  vrrEnabled = config.features.gui.vrr.enable or false;
  hy3Pkg =
    if hy3Enabled
    then hy3.packages.${pkgs.stdenv.hostPlatform.system}.hy3
    else null;
  hyprsplitPkg = pkgs.hyprlandPlugins.hyprsplit;
  hyprVrrPkg =
    if vrrEnabled
    then lib.attrByPath ["hyprlandPlugins" "hyprland-vrr"] null pkgs
    else null;
  pluginEntries =
    (lib.optional (hy3Enabled && hy3Pkg != null) {
      path = "${hy3Pkg}/lib/libhy3.so";
      pkg = hy3Pkg;
    })
    ++ (lib.optional hyprsplitEnabled {
      path = "${hyprsplitPkg}/lib/libhyprsplit.so";
      pkg = hyprsplitPkg;
    })
    ++ (lib.optional (vrrEnabled && hyprVrrPkg != null) {
      path = "${hyprVrrPkg}/lib/libhyprland-vrr.so";
      pkg = hyprVrrPkg;
    });
in
  mkIf config.features.gui.enable (lib.mkMerge [
    # Local helper: safe Hyprland reload that ensures Quickshell is started if absent
    (let
      mkLocalBin = import ../../../../packages/lib/local-bin.nix {inherit lib;};
    in
      mkLocalBin "hypr-reload" ''        #!/usr/bin/env bash
                set -euo pipefail
                # Reload Hyprland config (ignore failure to avoid spurious errors)
                hyprctl reload >/dev/null 2>&1 || true
                # Give Hypr a brief moment to settle before (re)starting quickshell
                sleep 0.15
                # Start quickshell only if not already active; 'start' is idempotent.
                systemctl --user start quickshell.service >/dev/null 2>&1 || true
      '')
    # Removed custom kb-layout-next wrapper; rely on Hyprland dispatcher and XKB options
    {
      wayland.windowManager.hyprland = {
        enable = true;
        package = pkgs.hyprland;
        portalPackage = null;
        settings = let
          hy3Enabled = config.features.gui.hy3.enable or false;
        in {
          source =
            [
              # Apply permissions first so plugin load is allowed (even without hy3)
              "${config.xdg.configHome}/hypr/permissions.conf"
            ]
            ++ lib.optionals hy3Enabled [
              # Load plugins (hy3) before the rest of the config
              "${config.xdg.configHome}/hypr/plugins.conf"
            ]
            ++ ["${config.xdg.configHome}/hypr/init.conf"];
        };
        systemd.variables = ["--all"];
      };
      home.packages = config.lib.neg.pkgsList (
        let
          groups = {
            core =
              [
                pkgs.hyprcursor # modern cursor theme format (replaces xcursor)
                pkgs.hypridle # idle daemon
                pkgs.hyprpicker # color picker
                pkgs.hyprpolkitagent # polkit agent
                pkgs.hyprprop # xprop-like tool for Hyprland
                pkgs.hyprutils # core utils for Hyprland
                pkgs.pyprland # Hyprland plugin system
                pkgs.upower # power management daemon
              ]
              ++ lib.optional (raiseProvider != null) (raiseProvider pkgs);
            qt = [
              pkgs.hyprland-qt-support # Qt integration fixes
              pkgs.hyprland-qtutils # Qt helper binaries (hyprland-qt-helper)
              pkgs.kdePackages.qt6ct # Qt6 config tool
            ];
            tools = [hyprWinList]; # helper: list windows from Hyprctl JSON
          };
          flags = {
            core = true;
            tools = true;
            qt = config.features.gui.qt.enable;
          };
        in
          config.lib.neg.mkEnabledList flags groups
      );
      programs.hyprlock.enable = true;
    }
    # Ensure polkit agent starts in a Wayland session and uses the graphical preset.
    {
      systemd.user.services.hyprpolkitagent = lib.mkMerge [
        {
          Unit.Description = "Hyprland Polkit Agent";
          Service = {
            ExecStart = let
              exe = lib.getExe' pkgs.hyprpolkitagent "hyprpolkitagent";
            in "${exe}";
            Environment = [
              "QT_QPA_PLATFORM=wayland"
              "XDG_SESSION_TYPE=wayland"
            ];
            Restart = "on-failure";
            RestartSec = "2s";
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["graphical"];})
      ];
    }
    # Core config files from repo
    (lib.mkMerge (map mkHyprSource coreFiles))
    # init.conf variants
    (mkIf (config.features.gui.hy3.enable or false) (mkHyprSource "init.conf"))
    (mkIf (! (config.features.gui.hy3.enable or false)) (
      xdg.mkXdgSource "hypr/init.conf" {
        source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/user/gui/hypr/conf/init.nohy3.conf";
        recursive = false;
        force = true;
      }
    ))
    # bindings.conf variants
    (mkIf (config.features.gui.hy3.enable or false) (mkHyprSource "bindings.conf"))
    (mkIf (! (config.features.gui.hy3.enable or false)) (
      xdg.mkXdgSource "hypr/bindings.conf" {
        source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/user/gui/hypr/conf/bindings.nohy3.conf";
        recursive = false;
        force = true;
      }
    ))
    # Dynamically generated plugin loader (hy3 only)
    (mkIf (pluginEntries != []) (
      let
        pluginLines = lib.concatMapStringsSep "\n" (entry: "plugin = ${entry.path}") pluginEntries;
        pluginPkgs = map (entry: entry.pkg) pluginEntries;
      in
        lib.mkMerge [
          (xdg.mkXdgText "hypr/plugins.conf" ''
            # Hyprland plugins
            ${pluginLines}
          '')
          {xdg.configFile."hypr/plugins.conf".force = true;}
          {home.packages = pluginPkgs;}
        ]
    ))
    (mkIf (vrrEnabled && hyprVrrPkg == null) {
      warnings = [
        "hyprland-vrr plugin requested, but `pkgs.hyprlandPlugins.hyprland-vrr` is missing in the current nixpkgs revision; skipping plugin load."
      ];
    })
  ])
