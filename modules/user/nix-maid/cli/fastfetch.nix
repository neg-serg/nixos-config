# Black-metal blizzard logo generator + wrappers (fastfetch).
# Reproducible tools: the animated WebP logos are generated on demand from
# the user's reference image; the logos/ dir is created at runtime.
{
  lib,
  config,
  neg,
  ...
}:
{
  config = lib.mkIf (config.lib.neg.enabled "cli") (
    neg.mkHomeFiles {
      ".local/share/fastfetch/make_blizzard.py".source =
        config.lib.neg.path "files/fastfetch/make_blizzard.py";
      ".local/share/fastfetch/blizzard.sh".source = config.lib.neg.path "files/fastfetch/blizzard.sh";
      ".local/share/fastfetch/blizzard.sh".executable = true;
      ".local/share/fastfetch/fetch".source = config.lib.neg.path "files/fastfetch/fetch";
      ".local/share/fastfetch/fetch".executable = true;
      ".local/bin/fetch".source = config.lib.neg.path "files/fastfetch/fetch";
      ".local/bin/fetch".executable = true;
    }
  );
}
