{
  lib,
  pkgs,
  config,
  negLib,
  ...
}: let
  cfg = config.features.dev.unreal;
  inherit
    (lib)
    mkOption
    mkEnableOption
    types
    mkIf
    mkMerge
    escapeShellArg
    getExe
    optionals
    getName
    mkAfter
    makeBinPath
    ;
  defaultRoot = "${config.home.homeDirectory}/games/UnrealEngine";
in {
  options.features.dev.unreal = {
    enable = (mkEnableOption "enable Unreal Engine 5 tooling") // {default = false;};
    root = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''Checkout directory for Unreal Engine sources. Defaults to "${defaultRoot}".'';
      example = "/mnt/storage/UnrealEngine";
    };
    repo = mkOption {
      type = types.str;
      default = "git@github.com:EpicGames/UnrealEngine.git";
      description = "Git URL used by ue5-sync (requires EpicGames/UnrealEngine access).";
    };
    branch = mkOption {
      type = types.str;
      default = "5.4";
      description = "Branch or tag to sync from the Unreal Engine repository.";
    };
    useSteamRun = mkOption {
      type = types.bool;
      default = true;
      description = "Wrap Unreal Editor launch via steam-run to provide FHS runtime libraries.";
    };
  };

  config = mkIf cfg.enable (
    let
      root =
        if cfg.root != null
        then cfg.root
        else defaultRoot;
      inherit (cfg) repo branch useSteamRun;
      rootEsc = escapeShellArg root;
      repoEsc = escapeShellArg repo;
      branchEsc = escapeShellArg branch;
      editorBinary = "${root}/Engine/Binaries/Linux/UnrealEditor";
      editorEsc = escapeShellArg editorBinary;
      steamRunExe = getExe pkgs.steam-run;
      packagesInfo = import (negLib.repoRoot + "/modules/dev/unreal/packages.nix") {
        inherit lib pkgs useSteamRun;
      };
      clangSuite = packagesInfo.clangSuite;
      icuLibPath = "${lib.getLib pkgs.icu}/lib";
      opensslLibPath = "${lib.getLib pkgs.openssl}/lib";
      zlibLibPath = "${lib.getLib pkgs.zlib}/lib";
      libPaths = lib.concatStringsSep ":" [icuLibPath opensslLibPath zlibLibPath];
      icuDataPath = "${pkgs.icu}/share/icu";
      cacheRoot = config.xdg.cacheHome or "${config.home.homeDirectory}/.cache";
      toolchainCacheRoot = "${cacheRoot}/ue-toolchain";

      editorScript = ''
        #!/usr/bin/env bash
        set -euo pipefail

        root=${rootEsc}
        editor=${editorEsc}

        if [ ! -x "$editor" ]; then
          echo "Unreal Editor binary not found at $editor" >&2
          echo "Use ue5-build after syncing the sources." >&2
          exit 1
        fi

        ${
          if useSteamRun
          then "exec ${steamRunExe} \"$editor\" \"$@\""
          else "exec \"$editor\" \"$@\""
        }
      '';

      buildScript = ''
        #!/usr/bin/env bash
        set -euo pipefail

        root=${rootEsc}

        # Use the Nix-provided SDK instead of Epic's bundled dotnet, which
        # relies on a glibc loader path that does not exist on NixOS.
        export UE_USE_SYSTEM_DOTNET=1
        export PATH="${makeBinPath [pkgs.dotnet-sdk_8 pkgs.llvmPackages_20.llvm clangSuite pkgs.protobuf pkgs.grpc]}:$PATH"

        toolchain_root="${toolchainCacheRoot}"
        toolchain_version="v26_clang-20.1.8-rockylinux8"
        multiarch_root="$toolchain_root/$toolchain_version"
        arch_triplet="x86_64-unknown-linux-gnu"
        toolchain_bin="$multiarch_root/$arch_triplet/bin"

        mkdir -p "$toolchain_bin"

        link_tool() {
          local src="$1"
          local dest="$toolchain_bin/$(basename "$src")"
          if [ -x "$src" ]; then
            ln -sf "$src" "$dest"
          fi
        }

        for exe in clang clang++; do
          link_tool "${clangSuite}/bin/$exe"
        done

        for exe in llvm-ar llvm-objcopy llvm-nm llvm-ranlib llvm-strip llvm-size llvm-readobj llvm-symbolizer; do
          link_tool "${pkgs.llvmPackages_20.llvm}/bin/$exe"
        done

        link_tool "${pkgs.llvmPackages_20.lld}/bin/ld.lld"

        printf '%s\n' "$toolchain_version" > "$multiarch_root/ToolchainVersion.txt"

        export LINUX_MULTIARCH_ROOT="$multiarch_root"
        export UE_SDKS_ROOT="$toolchain_root"
        export PATH="$toolchain_bin:$PATH"

        if ! command -v dotnet >/dev/null 2>&1; then
          echo "dotnet executable not found on PATH" >&2
          echo "Ensure dotnet-sdk_8 is installed via Home Manager." >&2
          exit 1
        fi

        if [ -z "''${DOTNET_ROOT:-}" ]; then
          dotnet_real="$(readlink -f "$(command -v dotnet)")"
          export DOTNET_ROOT="$(dirname "$dotnet_real")"
        fi

        export UE_DOTNET_DIR="$DOTNET_ROOT"
        export PROTOBUF_PROTOC="${pkgs.protobuf}/bin/protoc"
        export GRPC_PROTOC_PLUGIN="${pkgs.grpc}/bin/grpc_csharp_plugin"
        export PROTOBUF_TOOLS_OS=linux
        export PROTOBUF_TOOLS_CPU=x64
        export LLVM_AR="${pkgs.llvmPackages_20.llvm}/bin/llvm-ar"
        export LLVM_OBJCOPY="${pkgs.llvmPackages_20.llvm}/bin/llvm-objcopy"
        export AR="$LLVM_AR"
        export OBJCOPY="$LLVM_OBJCOPY"

        if [ ! -d "$root/.git" ]; then
          echo "Unreal Engine checkout not found at $root" >&2
          echo "Run ue5-sync first (requires EpicGames/UnrealEngine access)." >&2
          exit 1
        fi

        if [ -n "''${LD_LIBRARY_PATH:-}" ]; then
          export LD_LIBRARY_PATH="${libPaths}:''${LD_LIBRARY_PATH}"
        else
          export LD_LIBRARY_PATH="${libPaths}"
        fi
        export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=0
        if [ -z "''${ICU_DATA:-}" ]; then
          export ICU_DATA="${icuDataPath}"
        fi

        pushd "$root" >/dev/null
        trap 'popd >/dev/null' EXIT

        if [ -z ''${UE5_SKIP_SETUP:-} ]; then
          echo "[ue5-build] Running Setup.sh (set UE5_SKIP_SETUP=1 to skip)"
          ./Setup.sh
        else
          echo "[ue5-build] Skipping Setup.sh (UE5_SKIP_SETUP=1)"
        fi

        if [ -z ''${UE5_SKIP_PROJECT_FILES:-} ]; then
          echo "[ue5-build] Running GenerateProjectFiles.sh (set UE5_SKIP_PROJECT_FILES=1 to skip)"
          ./GenerateProjectFiles.sh
        else
          echo "[ue5-build] Skipping GenerateProjectFiles.sh (UE5_SKIP_PROJECT_FILES=1)"
        fi

        target="UnrealEditor"
        platform="Linux"
        configuration="Development"

        if [ $# -gt 0 ]; then
          target="$1"
          shift
        fi
        if [ $# -gt 0 ]; then
          platform="$1"
          shift
        fi
        if [ $# -gt 0 ]; then
          configuration="$1"
          shift
        fi

        ./Engine/Build/BatchFiles/Linux/Build.sh "$target" "$platform" "$configuration" "$@"
      '';

      syncScript = ''
        #!/usr/bin/env bash
        set -euo pipefail

        root=${rootEsc}
        repo=${repoEsc}
        branch=${branchEsc}

        mkdir -p "$(dirname "$root")"

        if [ ! -d "$root/.git" ]; then
          echo "[ue5-sync] Cloning $repo to $root (branch $branch)"
          if ! git clone --recursive --branch "$branch" "$repo" "$root"; then
            echo "Clone failed. Ensure your GitHub account has been linked with Epic Games and SSH access is configured." >&2
            exit 1
          fi
        else
          echo "[ue5-sync] Updating existing checkout at $root"
          git -C "$root" fetch --tags origin
          git -C "$root" checkout "$branch"
          git -C "$root" pull --ff-only origin "$branch"
          git -C "$root" submodule sync --recursive
          git -C "$root" submodule update --init --recursive
        fi

        git -C "$root" lfs install --local
        git -C "$root" lfs pull
      '';

    in
      mkMerge [
        {
          assertions = [
            {
              assertion = config.features.dev.enable or false;
              message = "Enable features.dev.enable to use Unreal Engine tooling.";
            }
          ];

          home.sessionVariables = {
            UE5_ROOT = root;
          };
          # Toolchain packages now install via modules/dev/unreal/default.nix.

          features.allowUnfree.extra =
            [(getName pkgs.dotnet-sdk_8)]
            ++ optionals useSteamRun [
              (getName pkgs.steam-run)
              (getName pkgs.steam-unwrapped)
            ];

          features.excludePkgs = mkAfter ["clang-tools"];

          # Removed obsolete ue5-sync GitHub access warning.
        }
        (
          let
            mkLocalBin = negLib.mkLocalBin;
          in
            lib.mkMerge [
              (mkLocalBin "ue5-editor" editorScript)
              (mkLocalBin "ue5-build" buildScript)
              (mkLocalBin "ue5-sync" syncScript)
            ]
        )
      ]
  );
}
