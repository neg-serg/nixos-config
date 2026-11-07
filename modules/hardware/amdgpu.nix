{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.features.hardware.amdgpu;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.rocm.enable {
      hardware.graphics = {
        extraPackages = [
          pkgs.rocmPackages.clr # Radeon Open Compute Common Language Runtime
          pkgs.rocmPackages.clr.icd # OpenCL ICD loader for ROCm
          pkgs.rocmPackages.rocminfo # ROCm info utility
          pkgs.rocmPackages.rocm-runtime # ROCm runtime
        ];
      };

      environment.systemPackages = [
        pkgs.rocmPackages.rocm-smi # ROCm System Management Interface
      ];

      # This is necesery because many programs hard-code the path to hip
      systemd.tmpfiles.rules = [
        "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
      ];
    })

    # SteamVR's vrcompositor asks for a high-priority Vulkan queue. NixOS runs
    # Steam inside a bwrap user namespace, where file capabilities cannot grant
    # CAP_SYS_NICE to vrcompositor-launcher, so SteamVR disables async
    # reprojection. The vendored patch removes amdgpu's check instead; it
    # weakens GPU scheduling privileges for every local process (see the patch
    # header). VR works without it, only async reprojection stays unavailable.
    (lib.mkIf cfg.ignoreCtxPrivileges {
      boot.kernelPatches = [
        {
          name = "amdgpu-allow-any-ctx-priority";
          patch = config.lib.neg.path "files/patches/amdgpu-allow-any-ctx-priority.patch";
        }
      ];
    })
  ];
}
