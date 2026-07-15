{
  lib,
  inputs,
  config,
  pkgs,
  ...
}:
let
  repoRoot = inputs.self;
  caches = import ./caches.data.nix;
in
{
  sops.age = {
    generateKey = true;
    keyFile = "/var/lib/sops-nix/key.txt";
    sshKeyPaths = [ ];
  };

  sops.secrets."github-netrc" = {
    sopsFile = repoRoot + "/secrets/github-netrc.sops.yaml";
    owner = config.users.main.name or "neg";
    mode = "0600";
  };

  nix = {
    # package left for Determinate module to set
    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
    settings = {
      accept-flake-config = true;
      builders-use-substitutes = true;
      show-trace = false;
      netrc-file = config.sops.secrets."github-netrc".path;
      system-features = [
        "big-parallel"
        "nixos-test"
        "benchmark"
        "kvm"
      ];
      # Keep build outputs/derivations between GCs for faster rebuilds
      keep-outputs = true;
      keep-derivations = true;
      fallback = true;
      experimental-features = [
        "auto-allocate-uids" # allow nix to automatically pick UIDs, rather than creating nixbld* user accounts
        "flakes" # flakes for reprodusability
        "nix-command" # new nix interface
        "parallel-eval" # parallel nix evaluation (Determinate Nix)
        "pipe-operators" # |> syntax for cleaner function chains
        "ca-derivations" # content-addressed derivations: store paths identified by output hash
        "blake3-hashes" # BLAKE3: faster parallel hashing for store paths
        "wasm-builtin" # builtins.wasm: call WebAssembly functions from Nix evaluation
        "wasm-derivations" # system = "wasm32-wasip1": platform-independent derivations
      ];
      eval-cache = true;
      eval-system = "x86_64-linux"; # only evaluate for host platform, skip aarch64
      allow-import-from-derivation = false;
      trusted-users = [
        "root"
        (config.users.main.name or "neg")
      ];
      connect-timeout = 15;
      stalled-download-timeout = 120;
      http-connections = 12;
      cores = 32; # all threads on 9950X3D per build, linking is single-threaded anyway
      max-jobs = 2; # 2 parallel builds, ~30-35GB peak — fits 40GB MemoryMax
      min-free = 4096; # MB reserved for ZFS during builds (ARC + build pressure)
      build-poll-interval = 3; # seconds between polling for finished builds
      log-lines = 50; # lines of build output to show on failure
      max-silent-time = 1200; # kill stuck builders after 20 min of no output
      use-xdg-base-directories = true;
      warn-dirty = false; # Disable annoying dirty warn
      download-attempts = 5;
      # narinfo-cache-negative-ttl default is 3600 (1 hour)
      # Deduplication via weekly nix.optimise timer instead of per-write
      auto-optimise-store = false;
      preallocate-contents = true; # Reduce ZFS CoW fragmentation by pre-allocating store paths
      lazy-locks = true; # Lazy flake.lock loading for faster eval
      # Expose ccache directory to sandboxed builds
      extra-sandbox-paths = [ "/cache" ];
    }
    // caches;

    # Override Determinate Nix with patched binary (opt/cpp-hotpaths:
    #   - git status skip for unmodified flake sources
    #   - coerceToString cache per derivation
    #   - attr name memoization)
    # Disabled during benchmarks to avoid --impure overhead from builtins.path
    # package = lib.mkForce (
    #   pkgs.runCommand "nix-patched-3.21.5" {
    #     pname = "nix";
    #     version = "3.21.5";
    #   } ''
    #     src=${builtins.path {
    #       path = /home/neg/src/nix-src/build/src;
    #       name = "nix-patched-build";
    #     }}
    #     mkdir -p $out/bin
    #
    #     cp $src/nix/nix $out/bin/nix
    #
    #     for dir in libutil libstore libexpr libfetchers libflake libmain libcmd; do
    #       mkdir -p $out/$dir
    #       # Copy only .so files/symlinks, skip .p/ directories with .o files
    #       find $src/$dir -maxdepth 1 \( -type f -o -type l \) -name '*.so*' \
    #         -exec cp -d --no-preserve=mode {} $out/$dir/ \;
    #     done
    #   ''
    # );
    gc = {
      automatic = lib.mkDefault true;
      dates = "weekly";
      options = "--delete-older-than 21d";
    };
    optimise = {
      # Run nix-store --optimise via systemd timer
      automatic = lib.mkDefault true;
      dates = "weekly";
    };
    registry.nixpkgs.flake = inputs.nixpkgs;
    daemonCPUSchedPolicy = "batch";
  };

  # Memory protection: cgroups v2 caps RAM+swap for nix-daemon.
  # Without MemorySwapMax, swap is unlimited — builds thrash instead of dying.
  systemd.services.nix-daemon.serviceConfig = {
    MemoryMax = "40G"; # hard physical RAM cap (~2/3 of 60GB)
    MemorySwapMax = "42G"; # RAM+swap cap: only 2GB swap allowed
  };

  # Determinate Nix overrides netrc-file in /etc/nix/nix.conf after including
  # nix.custom.conf, so sops-managed netrc path doesn't take effect.
  # This service copies the sops-decrypted netrc to the Determinate-managed path.
  systemd.services.fix-determinate-netrc = {
    description = "Copy sops-decrypted netrc to Determinate Nix path";
    wantedBy = [ "multi-user.target" ];
    after = [ "sops-nix.service" ];
    requires = [ "sops-nix.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      install -m 600 ${config.sops.secrets."github-netrc".path} /nix/var/determinate/netrc
    '';
  };

  # nixpkgs.config.rocmSupport moved to flake/pkgs-config.nix
}
