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
    environment.systemPackages = [
      # torch-rocm CLI: python3.14 env with ROCm PyTorch (RX 9070 XT).
      # env -u PYTHONPATH: the login shell may leak a py3.13 venv path which
      # breaks numpy in the 3.14 env.
      (pkgs.writeShellScriptBin "torch-rocm" ''
        exec env -u PYTHONPATH ${pkgs.torchRocmEnv}/bin/python "$@"
      '')
      pkgs.rocmPackages.rocm-smi # ROCm System Management Interface
    ];
  };
}
