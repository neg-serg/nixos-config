{
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  enable =
    (config.features.dev.enable or false)
    && (config.features.dev.ai.enable or false)
    && (config.features.dev.ai.antigravity.enable or false);
in
lib.mkIf enable (
  n.mkHomeFiles {
    # Antigravity (VS Code fork) settings
    ".config/Antigravity/User/settings.json".text = builtins.toJSON {
      "python.languageServer" = "Default";
      "redhat.telemetry.enabled" = true;
      "json.schemaDownload.enable" = true;
      "workbench.activityBar.location" = "bottom";
      "workbench.editor.showTabs" = "none";
      "workbench.colorTheme" = "Default Dark Modern";
    };
  }
)
