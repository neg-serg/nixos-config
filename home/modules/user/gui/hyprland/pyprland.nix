{
  lib,
  config,
  xdg,
  ...
}:
with lib;
  mkIf config.features.gui.enable (
    xdg.mkXdgConfigToml "hypr/pyprland.toml" {
      pyprland.plugins = [
        "fetch_client_menu"
        "scratchpads"
        "toggle_special"
      ];
      scratchpads = {
        im = {
          animation = "";
          command = "Telegram";
          class = "org.telegram.desktop";
          size = "30% 95%";
          position = "69% 2%";
          lazy = true;
          multi = true;
        };
        discord = {
          animation = "fromRight";
          command = "vesktop";
          class = "vesktop";
          size = "50% 40%";
          lazy = true;
          multi = true;
        };
        music = {
          animation = "";
          command = "kitty --class music -e rmpc";
          margin = "80%";
          class = "music";
          position = "15% 50%";
          size = "70% 40%";
          lazy = true;
          unfocus = "hide";
        };
        torrment = {
          animation = "";
          command = "kitty --class torrment -e rustmission";
          class = "torrment";
          position = "1% 0%";
          size = "98% 40%";
          lazy = true;
          unfocus = "hide";
        };
        teardown = {
          animation = "";
          command = "kitty --class teardown -e btop";
          class = "teardown";
          position = "1% 0%";
          size = "98% 50%";
          lazy = true;
        };
        mixer = {
          animation = "fromRight";
          command = "pwvucontrol";
          class = "com.saivert.pwvucontrol";
          lazy = true;
          size = "40% 90%";
          unfocus = "hide";
          multi = true;
        };
      };
    }
  )
