{
  lib,
  xdg,
  config,
  ...
}:
with lib;
  mkIf config.features.dev.enable (lib.mkMerge [
    # Git hooks via helper: ensure parent dir is real and mark as executable
    (xdg.mkXdgSource "git/hooks/pre-commit" {
      source = ./hooks/pre-commit.sh;
      executable = true;
    })
    (xdg.mkXdgSource "git/hooks/commit-msg" {
      source = ./hooks/commit-msg.sh;
      executable = true;
    })
  ])
