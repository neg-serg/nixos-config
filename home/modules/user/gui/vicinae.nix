{
  lib,
  config,
  pkgs,
  ...
}: let
  xdg = import ../../lib/xdg-helpers.nix {inherit lib pkgs;};
  vicinaeThemeNeg = import ./vicinae/themes/neg.nix;
  vicinaeFont =
    lib.attrByPath ["gtk" "font"] {
      name = "Iosevka";
      size = 10;
    }
    config;
  mkTitleCase = name: let
    str = builtins.toString name;
    len = lib.stringLength str;
    head =
      if len == 0
      then ""
      else lib.substring 0 1 str;
    tail =
      if len <= 1
      then ""
      else lib.substring 1 (len - 1) str;
  in
    if len == 0
    then str
    else "${lib.strings.toUpper head}${tail}";
  vicinaeIconTheme = mkTitleCase (lib.attrByPath ["gtk" "iconTheme" "name"] "kora" config);
  vicinaeSettings = {
    closeOnFocusLoss = false;
    faviconService = "google";
    font = {
      normal = vicinaeFont.name;
      family = vicinaeFont.name;
      inherit (vicinaeFont) size;
    };
    keybinding = "emacs";
    keybinds = {};
    popToRootOnClose = true;
    rootSearch.searchFiles = true;
    theme = {
      name = "neg";
      iconTheme = vicinaeIconTheme;
    };
    window = {
      csd = true;
      opacity = 0.98;
      rounding = 10;
    };
  };
  vicinaeSettingsFile =
    pkgs.writeText "vicinae-settings.json" (builtins.toJSON vicinaeSettings);
  emptyVicinaeConfig = pkgs.writeText "vicinae-empty.json" "{}";
in
  with lib;
  # Enable Vicinae when GUI is on and provide sane defaults.
    mkIf config.features.gui.enable (
      lib.mkMerge [
        {
          programs.vicinae = {
            enable = true;
            # Prefer Wayland layer-shell integration for proper stacking on Hyprland
            useLayerShell = true;
            # Autostart the daemon in graphical sessions via systemd user unit
            systemd = {
              enable = true;
              autoStart = true;
              target = "graphical-session.target";
            };
            # Local extension to avoid IFD (no remote fetch/build during eval)
            extensions = [
              (config.lib.vicinae.mkExtension {
                name = "neg-hello";
                src = ./vicinae/extensions/neg-hello;
              })
            ];
            # Walker-matched dark theme (neg) for Vicinae
            themes = {
              neg = vicinaeThemeNeg;
            };
          };
        }
        # Merge our desired defaults into vicinae.json without clobbering manual edits.
        {
          home.activation.vicinaeMergeConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
            cfg="${config.xdg.configHome}/vicinae/vicinae.json"
            mkdir -p "$(dirname "$cfg")"
            current="$cfg"
            if [ ! -s "$cfg" ]; then
              current=${emptyVicinaeConfig}
            fi
            tmp="$(mktemp)"
            ${pkgs.jq}/bin/jq -s 'reduce .[] as $item ({}; . * $item)' \
              ${vicinaeSettingsFile} "$current" > "$tmp"
            if ! cmp -s "$tmp" "$cfg" 2>/dev/null; then
              install -Dm644 "$tmp" "$cfg"
            fi
            rm -f "$tmp"
          '';
        }
      ]
    )
