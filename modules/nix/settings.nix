{
  lib,
  inputs,
  config,
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
      ];
      eval-cache = true;
      allow-import-from-derivation = false;
      trusted-users = [
        "root"
        (config.users.main.name or "neg")
      ];
      connect-timeout = 15;
      stalled-download-timeout = 120;
      http-connections = 32;
      cores = 4; # per build — each build gets 4 threads
      max-jobs = 16; # 16 physical cores × 2 threads = full utilisation
      min-free = 512; # MB reserved for ZFS during builds
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
    daemonIOSchedClass = "idle";
    daemonIOSchedPriority = 7;
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
