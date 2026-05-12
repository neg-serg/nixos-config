{
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkMerge [
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
          pkgs.libva-utils # vainfo, encode/decode probing
          pkgs.lact # linux amdgpu controller
          (pkgs.nvtopPackages.amd.override { intel = true; }) # GPU monitor showing AMD + Intel iGPU
          pkgs.vulkan-tools # vulkaninfo etc.
        ];
      };
    }
  ];
}
