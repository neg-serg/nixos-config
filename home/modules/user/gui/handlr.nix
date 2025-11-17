{
  lib,
  config,
  xdg,
  ...
}:
lib.mkIf (config.features.gui.enable or false)
(xdg.mkXdgConfigToml "handlr/handlr.toml" {
  enable_selector = false;
  selector = "rofi -dmenu -p 'Open With: ❯>'";
})
