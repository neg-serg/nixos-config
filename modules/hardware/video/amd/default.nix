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
            pkgs.rocmPackages.clr.icd
          ];
        };
        amdgpu.opencl.enable = true;
      };
      environment = {
        variables.AMD_VULKAN_ICD = "RADV";
        systemPackages = [
          pkgs.clinfo # show info about opencl
          pkgs.rocmPackages.rocminfo
          pkgs.rocmPackages.rocm-smi
          pkgs.mesa-demos # contains glxinfo/glxgears
          pkgs.libva-utils # vainfo, encode/decode probing
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
