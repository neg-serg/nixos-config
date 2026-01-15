{
  lib,
  inputs,
  pkgs,
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
    package = pkgs.lix; # Powerful package manager that makes package management re...
    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
    settings = {
      accept-flake-config = true;
      builders-use-substitutes = true;
      show-trace = false;
      netrc-file = config.sops.secrets."github-netrc".path;
      system-features = [
        "big-parallel"
      ];
      fallback = true;
      experimental-features = [
        "auto-allocate-uids" # allow nix to automatically pick UIDs, rather than creating nixbld* user accounts
        "flakes" # flakes for reprodusability
        "nix-command" # new nix interface
      ];
      eval-cache = true;
      allow-import-from-derivation = false;
      trusted-users = [
        "root"
        (config.users.main.name or "neg")
      ];
      connect-timeout = 3; # Aggressive: bail quickly on slow caches
      stalled-download-timeout = 3; # Aggressive: abort stalled downloads fast
      http-connections = 3; # Limit parallel HTTP connections
      cores = 0; # Use all available cores per build
      max-jobs = "auto"; # Use all available cores
      use-xdg-base-directories = true;
      warn-dirty = false; # Disable annoying dirty warn
      download-attempts = 1; # Fast failure on unavailable caches
      narinfo-cache-negative-ttl = 0; # Always re-check for previously missing paths
      # Deduplication via weekly nix.optimise timer instead of per-write
      auto-optimise-store = false;
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
  # nixpkgs.config.rocmSupport moved to flake/pkgs-config.nix
}
