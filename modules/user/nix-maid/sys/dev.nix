{
  pkgs,
  lib,
  config,

  ...
}:
let

  cfg = config.features.dev;
  enableIac = cfg.enable && (cfg.pkgs.iac or false);
  enableCpp = cfg.enable && (cfg.cpp.enable or false);

  # ccache-aware compiler wrappers (bash scripts that exec ccache /real/gcc)
  # Scripts — NOT symlinks — so ccache can always resolve the real compiler path.
  ccacheGcc = pkgs.runCommand "ccache-gcc" {
    meta.priority = 4; # higher priority than default (5), so gcc/g++/c++ wrappers win over raw gcc
    inherit (pkgs) gcc ccache bash;
  } ''
    mkdir -p "$out/bin"
    for comp in gcc g++ c++; do
      realComp="$gcc/bin/$comp"
      cat > "$out/bin/$comp" << WRAPPER
  #!$bash/bin/bash -e
  exec "$ccache/bin/ccache" "$realComp" "\$@"
  WRAPPER
      chmod +x "$out/bin/$comp"
    done
  '';

in
{
  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      {
        # Packages
        environment.systemPackages = [
          pkgs.direnv # Extension for your shell to load/unload env vars
          pkgs.nix-direnv # A fast, persistent use_nix implementation for direnv
          pkgs.nh # Yet another nix helper (CLI for NixOS/Home Manager)

        ]
        ++ lib.optionals enableIac [ ]
        ++ lib.optionals enableCpp [
          # C/C++ toolchain with ccache
          ccacheGcc # ccache-wrapper for gcc/g++/c++ (higher priority via symlinkJoin)
          pkgs.ccache # ccache CLI binary itself
          pkgs.gcc # compiler runtime libs
          pkgs.cmake # build system
          pkgs.ninja # fast build tool
        ];

        # Environment Variables
        environment.variables = {
          # C/C++ compilation cache
          CCACHE_DIR = "/cache";
          CCACHE_COMPRESS = "1";
          CCACHE_MAXSIZE = "50G";
          CCACHE_SLOPPINESS = "file_macro,time_macros,include_file_ctime,include_file_mtime";
          CMAKE_C_COMPILER_LAUNCHER = "ccache";
          CMAKE_CXX_COMPILER_LAUNCHER = "ccache";

          # Rust
          CARGO_HOME = "${config.users.users.neg.home}/.local/share/cargo";
          RUSTUP_HOME = "${config.users.users.neg.home}/.local/share/rustup";

          # Haskell
          GHCUP_USE_XDG_DIRS = "1";

          # Go
          GOMODCACHE = "${config.users.users.neg.home}/.cache/gomod";

          # CUDA / LLVM
          CUDA_CACHE_PATH = "${config.users.users.neg.home}/.cache/cuda";
          LLVM_PROFILE_FILE = "${config.users.users.neg.home}/.cache/llvm/%h-%p-%m.profraw";

          # Python
          PYLINTHOME = "${config.users.users.neg.home}/.config/pylint";

          # Java
          _JAVA_OPTIONS = "-Djava.util.prefs.userRoot=${config.users.users.neg.home}/.config/java";

          # Hardware / Firmware
          QMK_HOME = "${config.users.users.neg.home}/src/qmk_firmware";

          # VM
          VAGRANT_HOME = "${config.users.users.neg.home}/.local/share/vagrant";
        };
      }
    ]

  );
}
