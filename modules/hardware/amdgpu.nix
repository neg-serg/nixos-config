{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.features.hardware.amdgpu;
in {
  config = lib.mkIf cfg.rocm.enable {
    hardware.graphics = {
      extraPackages = with pkgs; [
        rocmPackages.clr # Radeon Open Compute Common Language Runtime
        rocmPackages.clr.icd # OpenCL ICD loader for ROCm
        rocmPackages.rocminfo # ROCm info utility
        rocmPackages.rocm-runtime # ROCm runtime
      ];
    };

    environment.systemPackages = with pkgs; [
      rocmPackages.rocm-smi # ROCm System Management Interface
    ];

    # This is necesery because many programs hard-code the path to hip
    systemd.tmpfiles.rules = [
      "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
    ];
  };
}
