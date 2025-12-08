{
  lib,
  pkgs,
  config,
  xdg,
  ...
}: let
  guiEnabled = config.features.gui.enable or false;
  cfg = config.features.apps.discord.system24Theme or {};
  themeUrl = "https://raw.githubusercontent.com/refact0r/system24/main/theme/system24.theme.css";
  themeFile = pkgs.fetchurl {
    url = themeUrl;
    sha256 = "sha256-6Qx+10/3Nf7IF3VQmf/r76qOuHHlOOU0RpxppVe4slI=";
  };
  themePath = "${config.xdg.configHome}/Vencord/themes/system24.theme.css";
  settingsPath = "${config.xdg.configHome}/Vencord/settings/settings.json";
  themeEnabled = guiEnabled && (cfg.enable or false);
in {
  config = lib.mkMerge [
    (lib.mkIf themeEnabled (lib.mkMerge [
      (xdg.mkXdgSource "Vencord/themes/system24.theme.css" {source = themeFile;})
      {
        home.activation.vencordSystem24Theme = lib.hm.dag.entryAfter ["writeBoundary"] ''
          set -euo pipefail
          theme_path=${lib.escapeShellArg themePath}
          settings=${lib.escapeShellArg settingsPath}

          mkdir -p "$(dirname "$settings")"
          if [ ! -s "$settings" ]; then
            printf '%s\n' '{}' > "$settings"
          fi

          tmp="$(mktemp)"
          ${pkgs.jq}/bin/jq --arg theme "$theme_path" '
            .enabledThemes = ((.enabledThemes // []) + [$theme] | unique)
          ' "$settings" > "$tmp"
          install -Dm0644 "$tmp" "$settings"
          rm -f "$tmp"
        '';
      }
    ]))
    (lib.mkIf (guiEnabled && !themeEnabled) {
      home.activation.vencordSystem24ThemeCleanup = lib.hm.dag.entryAfter ["writeBoundary"] ''
        set -euo pipefail
        settings=${lib.escapeShellArg settingsPath}
        theme_path=${lib.escapeShellArg themePath}

        if [ -f "$settings" ]; then
          tmp="$(mktemp)"
          ${pkgs.jq}/bin/jq --arg theme "$theme_path" '
            .enabledThemes = (.enabledThemes // [] | map(select(. != $theme)))
          ' "$settings" > "$tmp"
          install -Dm0644 "$tmp" "$settings"
          rm -f "$tmp"
        fi
      '';
    })
  ];
}
