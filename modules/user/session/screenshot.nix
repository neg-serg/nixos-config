{ pkgs, ... }:
{
  environment.systemPackages = [
    # -- Screenshot / Recording --
    pkgs.grim # raw screenshot helper for clip wrappers
    pkgs.grimblast # Hyprland-friendly screenshots (grim+slurp+wl-copy)
    pkgs.slurp # select regions for grim/wlroots compositors
    pkgs.wf-recorder # screen recording
    # pkgs.satty # screenshot annotation (used in wlr-which-key bindings but not installed)
  ];
}
