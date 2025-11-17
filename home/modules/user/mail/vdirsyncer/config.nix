{
  lib,
  config,
  xdg,
  ...
}:
with lib;
  mkIf (config.features.mail.enable && config.features.mail.vdirsyncer.enable) (
    let
      tpl = builtins.readFile ./config.tpl;
      stateHome = config.xdg.stateHome or "$HOME/.local/state";
      xdgConfig = config.xdg.configHome;
      rendered = lib.replaceStrings ["@XDG_STATE@" "@XDG_CONFIG@"] [stateHome xdgConfig] tpl;
    in
      xdg.mkXdgText "vdirsyncer/config" rendered
  )
