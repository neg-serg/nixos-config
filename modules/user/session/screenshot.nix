{ pkgs, ... }:
{
  environment.systemPackages = [
    # -- Screenshot / Recording --
    pkgs.grim # raw screenshot helper for clip wrappers
    pkgs.slurp # select regions for grim/wlroots compositors
    pkgs.swappy # annotate a capture (the reference's screenshot editor, without a scene of its own)
    pkgs.wf-recorder # screen recording
    pkgs.gpu-screen-recorder # GPU-only screen recorder (ShadowPlay-like: replay buffer, per-monitor)
    pkgs.wayscriber # live screen annotation overlay (ZoomIt-like) with zoom/freeze/capture
  ];
}
