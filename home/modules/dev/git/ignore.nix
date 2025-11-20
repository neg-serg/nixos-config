{
  lib,
  xdg,
  config,
  ...
}:
with lib; let
  filesRoot = "${config.neg.hmConfigRoot}/files";
in
  mkIf config.features.dev.enable (
    # Link user excludes file from repo into ~/.config/git/ignore with guards
    xdg.mkXdgSource "git/ignore" {
      source = filesRoot + "/git/ignore";
      recursive = false;
    }
  )
