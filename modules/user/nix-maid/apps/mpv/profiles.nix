{
  config,
  lib,
  neg,
  ...
}:
{
  config = lib.mkIf (config.lib.neg.enabled "gui") (
    neg.mkHomeFiles {
      ".config/mpv/profiles.conf".text = builtins.readFile (
        config.lib.neg.path "files/mpv/profiles.conf"
      );
    }
  );
}
