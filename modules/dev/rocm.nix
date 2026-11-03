{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.dev.ai.rocm;
in
{
  config = lib.mkIf cfg.enable {
    # torch-rocm (a 7.7G Python env) moved to the `rocm` devshell and the
    # `nix run .#torch-rocm` app; only the monitoring CLI stays in the closure.
    environment.systemPackages = [
      pkgs.rocmPackages.rocm-smi # ROCm System Management Interface
    ];
  };
}
