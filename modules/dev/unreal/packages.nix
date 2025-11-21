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
      pkgs.git # UE sources pull from GitHub; CLI required
      pkgs.git-lfs # handle LFS assets in Epic repos
      pkgs.mono # Mono runtime for Unreal build tools
      pkgs.cmake # configure helper for ancillary libs
      pkgs.ninja # build tool favored by UE's generated projects
      (lib.lowPrio pkgs.python3) # scripts rely on python3 (low prio to avoid conflicts)
      clangSuite # bundled clang/clang-tools pinned to UE version
      pkgs.llvmPackages_20.llvm # LLVM libs for backend compatibility
      pkgs.llvmPackages_20.lld # LLD linker required by UE build chain
      pkgs.llvmPackages_20.libclang.lib # libclang for bindings/plugins
      pkgs.dotnet-sdk_8 # UnrealBuildTool requires modern dotnet SDK
      pkgs.protobuf # protoplugin build dependency
      pkgs.grpc # gRPC headers/libs for remote control modules
      pkgs.unzip # unzip helper for marketplace archives
      pkgs.p7zip # extract 7z-packed marketplace assets
      pkgs.rsync # sync intermediate files to sandboxes
      pkgs.which # ensure /usr/bin/which exists during scripts
    ]
    ++ lib.optionals useSteamRun [
      pkgs.steam-run # run UE editor with Steam runtime libs
    ];
in {
  inherit clangSuite packages;
}
