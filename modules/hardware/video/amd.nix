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
          pkgs.amdgpu_top # TUI AMD GPU usage monitor (GTK-free replacement for lact)
          (pkgs.nvtopPackages.amd.override { intel = true; }) # GPU monitor showing AMD + Intel iGPU
          pkgs.vulkan-tools # vulkaninfo etc.
        ];
      };
    }
  ];
}
