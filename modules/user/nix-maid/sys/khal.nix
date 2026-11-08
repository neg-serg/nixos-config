{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  cfg = config.features.mail; # Tie to mail feature as we're using it for calendars
  onDemand = config.lib.neg.onDemand pkgs;
in
{
  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      {
        environment.systemPackages = [
          (onDemand {
            name = "khal";
            attr = "khal";
            aliases = [ "ikhal" ];
          }) # CLI calendar application, built on first use
          # khal ships `ikhal.desktop` inside the package; the on-demand root is
          # not on XDG_DATA_DIRS, so the menu entry is recreated here.
          (pkgs.makeDesktopItem {
            name = "ikhal";
            desktopName = "ikhal";
            comment = "Terminal CLI calendar application";
            exec = "ikhal";
            icon = "x-office-calendar";
            terminal = true;
            categories = [
              "Office"
              "Calendar"
            ];
          })
        ];
      }
      (neg.mkHomeFiles {
        ".config/khal/config".text =
          builtins.replaceStrings [ "@TIMEZONE@" ] [ "${config.time.timeZone}" ]
            (builtins.readFile (config.lib.neg.path "files/config/khal/config"));
      })
    ]
  );
}
