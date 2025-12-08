{lib, ...}: {
  # Disabled by default; enable via services.guix.enable = true; when needed
  services.guix.enable = lib.mkDefault false;
}
