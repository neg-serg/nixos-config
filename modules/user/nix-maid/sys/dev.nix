{
  pkgs,
  lib,
  config,

  ...
}:
let

  cfg = config.features.dev;
  enableIac = cfg.enable && (cfg.pkgs.iac or false);

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
          pkgs.process-compose # Process orchestrator (docker-compose but for processes)
          pkgs.nix-search-tv # TUI for searching libraries on search.nixos.org
        ]
        ++ lib.optionals enableIac [
          # Ansible moved to separate feature (features.dev.ansible)
        ];

        # Environment Variables
        environment.variables = {
          # General Dev
          CCACHE_CONFIGPATH = "${config.users.users.neg.home}/.config/ccache.config";
          CCACHE_DIR = "${config.users.users.neg.home}/.cache/ccache";

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
