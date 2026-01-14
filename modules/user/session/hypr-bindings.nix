{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.users.main.name or "neg";
  userData = lib.attrByPath [ "users" "users" user ] { } config;
  userGroup = lib.attrByPath [ "group" ] user userData;
  homeDir = lib.attrByPath [ "home" ] "/home/${user}" userData;
  hyprAppsConf = pkgs.writeText "hypr-apps.conf" ''
    bind = $M4, d, exec, $pypr toggle teardown
    bind = $M4, e, exec, $pypr toggle im
    bind = $M4, f, exec, $pypr toggle music
    bind = $M4, t, exec, $pypr toggle torrment
    bind = $M4+$C, p, exec, $pypr toggle mixer

    bind = $M4, w, exec, raise --class $browser --launch $browser
    bind = $M4, x, exec, raise --class "term" --launch "kitty --class term"
    bind = $M4, q, exec, raise --class "nwim" --launch "kitty --class nwim -e /home/neg/.local/bin/v"
    bind = $M4, b, exec, raise --class "mpv" --launch "~/.local/bin/pl video"
    bind = $M4+$C, c, exec, raise --class "swayimg" --launch "swayimg ~/dw"
    bind = $M4+$S, c, exec, ~/.local/bin/wl
    bind = $M4+$C, v, exec, raise --class "Bazecor" --launch "bazecor"
    bind = $M4, g, exec, raise --class "steam" --launch "flatpak run com.valvesoftware.Steam || steam"
    bind = $M4, o, exec, raise --class "org.pwmt.zathura" --launch "zathura"
    bind = $M4+$C, n, exec, raise --class "Obsidian" --launch "flatpak run md.obsidian.Obsidian"
    bind = $M4+$S, o, exec, raise --class "obs" --launch "obs"
    bind = $M4+$S, l, exec, raise --class "lutris" --launch "flatpak run net.lutris.Lutris || lutris"
  '';
in
{
  systemd.tmpfiles.rules = [
    "d ${homeDir}/.config 0755 ${user} ${userGroup} -"
    "d ${homeDir}/.config/hypr 0755 ${user} ${userGroup} -"
    "d ${homeDir}/.config/hypr/bindings 0755 ${user} ${userGroup} -"
    "L+ ${homeDir}/.config/hypr/bindings/apps.conf - ${user} ${userGroup} - ${hyprAppsConf}"
  ];
}
