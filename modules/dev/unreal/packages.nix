{
  lib,
  pkgs,
  useSteamRun ? true,
}: let
  clangSuite = pkgs.buildEnv {
    name = "ue-clang-suite";
    paths = [pkgs.llvmPackages_20.clang pkgs.llvmPackages_20.clang-tools];
    ignoreCollisions = true;
  };
  packages =
    [
      pkgs.git
      pkgs.git-lfs
      pkgs.mono
      pkgs.cmake
      pkgs.ninja
      (lib.lowPrio pkgs.python3)
      clangSuite
      pkgs.llvmPackages_20.llvm
      pkgs.llvmPackages_20.lld
      pkgs.llvmPackages_20.libclang.lib
      pkgs.dotnet-sdk_8
      pkgs.protobuf
      pkgs.grpc
      pkgs.unzip
      pkgs.p7zip
      pkgs.rsync
      pkgs.which
    ]
    ++ lib.optionals useSteamRun [pkgs.steam-run];
in {
  inherit clangSuite packages;
}
