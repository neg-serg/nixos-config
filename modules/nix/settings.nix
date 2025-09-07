{
  inputs,
  pkgs,
  config,
  ...
}: {
  sops.age = {
    generateKey = true;
    keyFile = "/var/lib/sops-nix/key.txt";
    sshKeyPaths = [];
  };

  sops.secrets."github-netrc" = {
    sopsFile = ../../secrets/github-netrc.sops.yaml;
    owner = "root";
    mode = "0600";
  };

  nix = {
    package = pkgs.lix;
    nixPath = ["nixpkgs=${inputs.nixpkgs}"];
    settings = {
      accept-flake-config = true;
      show-trace = false;
      netrc-file = config.sops.secrets."github-netrc".path;
      substituters = [
        "https://cache.nixos.org/"
        "https://0uptime.cachix.org"
        "https://chaotic-nyx.cachix.org"
        "https://cuda-maintainers.cachix.org"
        "https://devenv.cachix.org"
        "https://ezkea.cachix.org"
        "https://cache.garnix.io"
        "https://hercules-ci.cachix.org"
        "https://hyprland.cachix.org"
        "https://neg-serg.cachix.org"
        "https://nix-community.cachix.org"
        "https://nix-gaming.cachix.org"
        "https://nixpkgs-unfree.cachix.org"
        "https://nixpkgs-wayland.cachix.org"
        "https://numtide.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "0uptime.cachix.org-1:ctw8yknBLg9cZBdqss+5krAem0sHYdISkw/IFdRbYdE="
        "chaotic-nyx.cachix.org-1:HfnXSw4pj95iI/n17rIDy40agHj12WfF+Gqk6SonIT8="
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
        # Garnix cache
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQKDXiAKk0B0="
        "hercules-ci.cachix.org-1:ZZeDl9Va+xe9j+KqdzoBZMFJHVQ42Uu/c/1/KMC5Lw0="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "neg-serg.cachix.org-1:MZ+xYOrDj1Uhq8GTJAg//KrS4fAPpnIvaWU/w3Qz/wo="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
        "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
        "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
        "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      ];
      system-features = [
        "big-parallel"
      ];
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
      cores = 0; # Use all available cores per build
      max-jobs = "auto"; # Use all available cores
      use-xdg-base-directories = true;
      warn-dirty = false; # Disable annoying dirty warn
      # Deduplicate the Nix store on writes
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 21d";
    };
    optimise = {
      # Run nix-store --optimise via systemd timer
      automatic = true;
      dates = "weekly";
    };
    registry.nixpkgs.flake = inputs.nixpkgs;
    daemonCPUSchedPolicy = "batch";
    daemonIOSchedClass = "idle";
    daemonIOSchedPriority = 7;
  };
  nixpkgs.config.allowUnfree = true;
}
