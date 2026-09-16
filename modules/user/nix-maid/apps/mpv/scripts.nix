{
  lib,
  config,
  neg,
  ...
}:
{
  config = lib.mkIf (config.lib.neg.enabled "gui") (
    neg.mkHomeFiles {
      ".config/mpv/script-opts/uosc.conf".text =
        config.lib.neg.readFile "files/mpv/script-opts/uosc.conf";
    }
  );
}
