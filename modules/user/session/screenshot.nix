{ pkgs, ... }:
{
  environment.systemPackages = [
    # -- Screenshot / Recording --
    pkgs.grim # raw screenshot helper for clip wrappers
    pkgs.slurp # select regions for grim/wlroots compositors
    pkgs.wf-recorder # screen recording
    pkgs.wayscriber # live screen annotation overlay (ZoomIt-like) with zoom/freeze/capture
  ];
}
