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

    profile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to the AutoFDO profile (gcov format) to use for optimization.";
      example = "/root/autofdo.prof";
    };
  };

  config = mkIf cfg.enable {
    # AutoFDO requires the kernel to be built with LLVM/Clang.
    # We override the latest kernel to use clangStdenv.
    # Users can override this by setting boot.kernelPackages manually,
    # but they must ensure it uses Clang.
    boot.kernelPackages = mkForce (
      pkgs.linuxPackagesFor (
        # custom kernel packages
        (pkgs.linuxPackages_latest.kernel.override {
          # use clang toolchain
          stdenv = pkgs.clangStdenv; # The default build environment for Unix packages in Nixpkgs
        }).overrideAttrs
          (old: {
            # Inject profile if provided
            makeFlags =
              (old.makeFlags or [ ])
              ++ (lib.optional (cfg.profile != null) "CLANG_AUTOFDO_PROFILE=${cfg.profile}");
          })
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

