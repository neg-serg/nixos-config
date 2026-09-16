{
  config,
  lib,
  neg,
  ...
}:
{
  config = lib.mkIf (config.lib.neg.enabled "gui") (
    neg.mkHomeFiles {
      ".config/mpv/profiles.conf".text = config.lib.neg.readFile "files/mpv/profiles.conf";
    }
  );
}
