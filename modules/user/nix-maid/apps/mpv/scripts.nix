{
  lib,
  config,
  neg,
  ...
}:
{
  config = lib.mkIf (config.lib.neg.enabled "gui") (
    neg.mkHomeFiles {
      ".config/mpv/script-opts/uosc.conf".text = builtins.readFile (
        config.lib.neg.path "files/mpv/script-opts/uosc.conf"
      );
    }
  );
}
