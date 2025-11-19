{
  lib,
  config,
  pkgs,
  xdg,
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
in
  mkIf config.features.gui.enable (lib.mkMerge [
    # Local helper: safe Hyprland reload that ensures Quickshell is started if absent
    (let
      mkLocalBin = import ../../../../../packages/lib/local-bin.nix {inherit lib;};
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
      home.packages = config.lib.neg.pkgsList (
        [hyprWinList]
        ++ lib.optionals (raiseProvider != null) [(raiseProvider pkgs)]
        ++ lib.optionals hy3Enabled [pkgs.hyprlandPlugins.hy3]
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
    (mkHyprSource "init.conf")
    (mkHyprSource "bindings.conf")
    (lib.mkMerge [
      (xdg.mkXdgText "hypr/hyprland.conf" ''
        exec-once = /run/current-system/sw/bin/dbus-update-activation-environment --systemd --all && systemctl --user stop hyprland-session.target && systemctl --user start hyprland-session.target

        source = ~/.config/hypr/init.conf

        permission = ${lib.getExe pkgs.grim}, screencopy, allow
        permission = ${lib.getExe pkgs.hyprlock}, screencopy, allow
      '')
      {xdg.configFile."hypr/hyprland.conf".force = true;}
    ])
    (mkIf hy3Enabled (
      let
        pluginPath = "${pkgs.hyprlandPlugins.hy3}/lib/libhy3.so";
      in
        lib.mkMerge [
          (xdg.mkXdgText "hypr/plugins.conf" ''
            # Hyprland plugins
            plugin = ${pluginPath}
          '')
          {xdg.configFile."hypr/plugins.conf".force = true;}
        ]
    ))
  ])
