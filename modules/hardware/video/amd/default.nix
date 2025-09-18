{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.hardware.video.amd;
in {
  options.hardware.video.amd.useMesaGit = lib.mkEnableOption "Enable Chaotic's mesa-git stack (bleeding-edge Mesa).";

  config = lib.mkMerge [
    (lib.mkIf cfg.useMesaGit {
      # Use mesa-git only when explicitly enabled (per-host opt-in)
      chaotic.mesa-git.enable = true;
    })
    {
      hardware = {
        graphics = {
          enable = true;
          enable32Bit = true; # 32-bit userspace for Steam/Wine
          extraPackages = [
            pkgs.rocmPackages.clr.icd
            pkgs.vaapiVdpau
            pkgs.libvdpau-va-gl
          ];
        };
        amdgpu.opencl.enable = true;
        amdgpu.amdvlk.enable = true;
      };
      environment = {
        variables.AMD_VULKAN_ICD = "RADV";
        systemPackages = [
          pkgs.clinfo # show info about opencl
          pkgs.rocmPackages.rocminfo
          pkgs.rocmPackages.rocm-smi
          pkgs.glxinfo # show info about glx
          pkgs.libva-utils # vainfo, encode/decode probing
          pkgs.vdpauinfo
          pkgs.lact # linux amdgpu controller
          (pkgs.nvtopPackages.amd.override {intel = true;})
          pkgs.vulkan-extension-layer
          pkgs.vulkan-tools
          pkgs.vulkan-validation-layers
        ];
      };
    }
  ];
}
