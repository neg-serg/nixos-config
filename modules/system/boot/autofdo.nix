# AutoFDO Support Module
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.boot.kernel.autofdo;
in
{
  options.boot.kernel.autofdo = {
    enable = mkEnableOption "Kernel AutoFDO support (requires Clang-built kernel)";
  };

  config = mkIf cfg.enable {
    # AutoFDO requires the kernel to be built with LLVM/Clang.
    # We override the latest kernel to use clangStdenv.
    # Users can override this by setting boot.kernelPackages manually,
    # but they must ensure it uses Clang.
    boot.kernelPackages = mkForce (
      pkgs.linuxPackagesFor (
        # custom kernel packages
        pkgs.linuxPackages_latest.kernel.override {
          # use clang toolchain
          stdenv = pkgs.clangStdenv; # The default build environment for Unix packages in Nixpkgs
        }
      )
    );

    boot.kernelPatches = [
      {
        name = "autofdo-config";
        patch = null;
        extraConfig = ''
          AUTOFDO_CLANG y
          DEBUG_INFO y
        '';
      }
    ];
  };
}
