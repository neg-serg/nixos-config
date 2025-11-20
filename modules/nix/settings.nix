{
  lib,
  inputs,
  pkgs,
  config,
  ...
}: let
  repoRoot = inputs.self;
  caches = import (repoRoot + "/nix/caches.nix");
in {
  sops.age = {
    generateKey = true;
    keyFile = "/var/lib/sops-nix/key.txt";
    sshKeyPaths = [];
  };

  sops.secrets."github-netrc" = {
    sopsFile = repoRoot + "/secrets/github-netrc.sops.yaml";
    owner = "root";
    mode = "0600";
  };

  nix = {
    package = pkgs.lix;
    nixPath = ["nixpkgs=${inputs.nixpkgs}"];
    settings =
      {
        accept-flake-config = true;
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
        trusted-users = [
          "root"
          (config.users.main.name or "neg")
        ];
        connect-timeout = 5; # Bail early on missing cache hits (thx to nyx)
        http-connections = 3; # Limit parallel HTTP connections (replaces obsolete binary-caches-parallel-connections)
        cores = 0; # Use all available cores per build
        max-jobs = "auto"; # Use all available cores
        use-xdg-base-directories = true;
        warn-dirty = false; # Disable annoying dirty warn
        download-attempts = 2;
        # Deduplicate the Nix store on writes
        auto-optimise-store = lib.mkDefault true;
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
  nixpkgs.config.allowUnfree = true;
}
