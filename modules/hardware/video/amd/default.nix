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
      chaotic.mesa-git.enable = false; # Use mesa-git only when explicitly enabled (per-host opt-in)
    })
    {
      hardware = {
        graphics = {
          enable = true;
          extraPackages = [
            pkgs.rocmPackages.clr.icd # OpenCL runtime for ROCm cards
          ];
        };
        amdgpu.opencl.enable = true;
      };
      environment = {
        variables.AMD_VULKAN_ICD = "RADV";
        systemPackages = [
          pkgs.clinfo # show info about opencl
          pkgs.rocmPackages.rocminfo # query ROCm driver for GPU topology
          pkgs.rocmPackages.rocm-smi # AMD SMI CLI (clocks, fans)
          pkgs.mesa-demos # contains glxinfo/glxgears
          pkgs.libva-utils # vainfo, encode/decode probing
          pkgs.lact # linux amdgpu controller
          (pkgs.nvtopPackages.amd.override {intel = true;}) # GPU monitor showing AMD + Intel iGPU
          pkgs.vulkan-extension-layer # inspect layers/extensions
          pkgs.vulkan-tools # vulkaninfo etc.
          pkgs.vulkan-validation-layers # debug validation for Vulkan apps
        ];
      };
    }
  ];
}
