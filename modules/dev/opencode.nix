{
  lib,
  config,
  pkgs,
  ...
}:
let
  enable =
    (config.features.dev.enable or false)
    && (config.features.dev.ai.enable or false)
    && (config.features.dev.ai.opencode.enable or false);
in
lib.mkIf enable {
  environment.systemPackages = [
    pkgs.opencode # AI coding agent built for the terminal
    pkgs.neg.opencode-antigravity-auth # The auth plugin
    (pkgs.makeDesktopItem {
      name = "opencode";
      desktopName = "OpenCode";
      exec = "${pkgs.writeShellScript "opencode-wrapper" ''
        PLUGIN_PATH="${pkgs.neg.opencode-antigravity-auth}/share/plugin"
        CONFIG_FILE="$HOME/.config/opencode/opencode.json"

        # Ensure config directory exists
        mkdir -p "$(dirname "$CONFIG_FILE")"

        if [ -f "$CONFIG_FILE" ]; then
          # Safely update the plugin path using jq
          tmp=$(mktemp)
          ${pkgs.jq}/bin/jq --arg path "$PLUGIN_PATH" '.plugin = [$path]' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        fi

        exec ${pkgs.opencode}/bin/opencode "$@"
      ''}";
      terminal = true;
      icon = "utilities-terminal";
      categories = [ "Development" ];
    })
  ];
}
