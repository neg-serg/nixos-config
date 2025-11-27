{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.hardware.video.nvidia.rtx5090;
in {
  options.hardware.video.nvidia.rtx5090 = {
    enable = lib.mkEnableOption "Enable NVIDIA RTX 5090 configuration.";
    useBetaDriver = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use the NVIDIA beta driver package for newest GPU support.";
    };
    wlrootsWorkarounds = {
      enable =
        (lib.mkEnableOption "Enable conservative wlroots workarounds (may disable HW cursors).")
        // {
          # Enable by default; user can opt-out on wlroots if desired
          default = true;
        };
    };
  };

  config = lib.mkIf cfg.enable {
    services.xserver.videoDrivers = ["nvidia"];
    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      nvidiaSettings = true;
      open = false;
      package = lib.mkDefault (
        if cfg.useBetaDriver
        then pkgs.linuxPackages.nvidiaPackages.beta
        else pkgs.linuxPackages.nvidiaPackages.stable
      );
    };

    # Wayland/NVIDIA friendly defaults
    environment = {
      # Session variables affect Wayland apps/XWayland
      sessionVariables =
        {
          # Prefer NVIDIA GBM path and vendor GLX for XWayland
          GBM_BACKEND = "nvidia-drm";
          __GLX_VENDOR_LIBRARY_NAME = "nvidia";
          # Allow VRR/G-Sync if compositor permits it
          __GL_VRR_ALLOWED = "1";
          __GL_GSYNC_ALLOWED = "1";
          # Ensure VA-API selects the NVIDIA shim when present
          LIBVA_DRIVER_NAME = lib.mkForce "nvidia";
        }
        // lib.optionalAttrs cfg.wlrootsWorkarounds.enable {
          # Safer default for wlroots to avoid cursor artifacts
          WLR_NO_HARDWARE_CURSORS = "1";
        };
    };

    # Provide VA-API shim for NVDEC on Wayland and useful tooling
    hardware.graphics.extraPackages = [
      pkgs.nvidia-vaapi-driver # NVENC/NVDEC VA-API shim for NVIDIA
    ];
    environment.systemPackages = lib.mkAfter [
      pkgs.vulkan-tools # vulkaninfo / debugging CLIs
      pkgs.libva-utils # vainfo to confirm NVDEC wiring
      (pkgs.nvtopPackages.nvidia or pkgs.nvtop) # GPU utilization monitor tuned for NVIDIA
    ];
  };
}
