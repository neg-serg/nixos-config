{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.cachyos;
in
{
  options.features.cachyos = {
    enable = lib.mkEnableOption "CachyOS performance tweaks (Kernel, SCX, Ananicy)";
  };

  config = lib.mkIf cfg.enable {
    # switch to CachyOS kernel with sched-ext support
    # Use znver4 optimized kernel if Zen 5 optimization is requested (closest match available)
    boot.kernelPackages = lib.mkForce (
      if (config.features.optimization.enable && config.features.optimization.zen5.enable) then
        pkgs.linuxPackages_cachyos-lto-znver4
      else
        pkgs.linuxPackages_cachyos
    );

    # Enable sched_ext (SCX) and use the configured scheduler
    # Note: scx package and service are provided by chaotic-nyx module
    services.scx = {
      enable = true;
      scheduler =
        if config.features.optimization.enable then
          config.features.optimization.scx.scheduler
        else
          "scx_rusty";
      # package = pkgs.scx; # Implicit from module
    };

    # Enable Ananicy-cpp for auto-prioritization
    services.ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
    };

    # Enable UKSMD (Userspace KSM helper) for memory deduplication
    # services.uksmd.enable = true;

    # Enable other CachyOS optimizations if available/safe
    # (e.g., specific sysctls are often handled by their kernel or ananicy)

    # Add cachyos-settings/tools if useful?
    # environment.systemPackages = [ pkgs.cachyos-settings ]; # often specific to Arch, check if available
  };
}
