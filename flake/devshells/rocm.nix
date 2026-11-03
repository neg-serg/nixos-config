{ pkgs, ... }: {
  # PyTorch with ROCm (gfx1201) lives here, not in the system closure: the env
  # is 7.7 GiB and only needed while doing GPU work. Enter the shell, or use
  # `nix run .#torch-rocm -- script.py` for one-off scripts.
  packages = [
    pkgs.torchRocmEnv # Python 3.14 + ROCm PyTorch (RX 9070 XT)
    pkgs.rocmPackages.rocm-smi # ROCm System Management Interface
    (pkgs.writeShellScriptBin "torch-rocm" ''
      exec env -u PYTHONPATH ${pkgs.torchRocmEnv}/bin/python "$@"
    '')
  ];
}
