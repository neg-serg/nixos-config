{
  config,
  lib,
  pkgs,
  settings ? {},
  ...
}: let
  bordersPlusPlusEnabled =
    lib.hasAttrByPath ["themeDetails" "bordersPlusPlus"] settings
    && (settings.themeDetails.bordersPlusPlus or false);
  dynamicCursorsPlugin = pkgs.hyprlandPlugins."dynamic-cursors";
  bordersPlusPlusPlugin = pkgs.hyprlandPlugins."borders-plus-plus";
in
  lib.mkIf config.features.gui.enable {
    wayland.windowManager.hyprland.plugins =
      [dynamicCursorsPlugin]
      ++ lib.optional bordersPlusPlusEnabled bordersPlusPlusPlugin;

    wayland.windowManager.hyprland.extraConfig =
      ''
        plugin {
            dynamic-cursors {
                enabled = true
                mode = stretch
                threshhold = 1
                stretch {
                    limit = 1500
                    function = linear
                }
                shake {
                    enabled = true
                    nearest = true
                    threshold = 5.0
                    base = 4.0
                    speed = 5.0
                    influence = 0.0
                    limit = 0.0
                    timeout = 2000
                    effects = false
                    ipc = false
                }
            }
        }
      ''
      + lib.optionalString bordersPlusPlusEnabled ''
        plugin {
          borders-plus-plus {
              add_borders = 2
              col.border_1 = rgb(020202)
              col.border_2 = rgb(020202)
              border_size_1 = 3
              border_size_2 = 10
              natural_rounding = yes
          }
        }
      '';
  }
