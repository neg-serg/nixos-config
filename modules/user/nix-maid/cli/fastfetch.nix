# Black-metal blizzard logo generator + wrappers (fastfetch).
# Reproducible tools: the animated WebP logos are generated on demand from
# the user's reference image; the logos/ dir is created at runtime.
# TODO(neg): drop this module (and files/fastfetch/) together with fastfetch;
# the on-demand launcher in cli/utils.nix is a stopgap, not the target state.
{
  lib,
  config,
  neg,
  pkgs,
  ...
}:
{
  config = lib.mkIf (config.lib.neg.enabled "cli") (
    neg.mkHomeFiles {
      # The Rust generator (packages/blizzard): the wrapper and `fetch` run it
      # from beside themselves, so the Python script is gone.
      ".local/share/fastfetch/blizzard".source = lib.getExe pkgs.neg.blizzard;
      ".local/share/fastfetch/blizzard.sh".source = config.lib.neg.live "files/fastfetch/blizzard.sh";
      ".local/share/fastfetch/blizzard.sh".executable = true;
      ".local/share/fastfetch/fetch".source = config.lib.neg.live "files/fastfetch/fetch";
      ".local/share/fastfetch/fetch".executable = true;
      ".local/bin/fetch".source = config.lib.neg.live "files/fastfetch/fetch";
      ".local/bin/fetch".executable = true;
    }
  );
}
