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
        };
        amdgpu.opencl.enable = false;
      };
      environment = {
        variables.AMD_VULKAN_ICD = "RADV";
        systemPackages = [
          pkgs.libva-utils # vainfo, encode/decode probing
          pkgs.lact # linux amdgpu controller
          (pkgs.nvtopPackages.amd.override { intel = true; }) # GPU monitor showing AMD + Intel iGPU
          pkgs.vulkan-tools # vulkaninfo etc.
        ];
      };
    }
  ];
}
