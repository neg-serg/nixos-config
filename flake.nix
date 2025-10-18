{
  description = "Neg-Serg configuration";
  inputs = {
    chaotic = {
      url = "git+https://github.com/chaotic-cx/nyx?ref=nyxpkgs-unstable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      # Pin Hyprland to a known-stable tag compatible with hy3
      url = "github:hyprwm/Hyprland?ref=v0.50.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Keep Hyprland-related inputs in lockstep with the pinned Hyprland flake
    hyprland-protocols.follows = "hyprland/hyprland-protocols";
    hyprland-qtutils.follows = "hyprland/hyprland-qtutils";
    # qt-support is nested under hyprland-qtutils
    hyprland-qt-support.follows = "hyprland/hyprland-qtutils/hyprland-qt-support";
    # xdg-desktop-portal-hyprland is named 'xdph' in Hyprland's flake inputs
    xdg-desktop-portal-hyprland.follows = "hyprland/xdph";
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nh = {
      url = "github:viperML/nh";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak = {url = "github:gmodena/nix-flatpak";}; # unstable branch. Use github:gmodena/nix-flatpak/?ref=<tag> to pin releases.
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pin nixpkgs to nixos-unstable so we get Hydra cache hits
    nixpkgs = {url = "github:NixOS/nixpkgs/nixos-unstable";};
    raise = {
      url = "github:neg-serg/raise";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Make Cachix caches available to all `nix {build,develop,run}` commands
  # Note: nixConfig must be a literal attrset (cannot import).
  nixConfig = {
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
      # Official NixOS cache (required for cache.nixos.org)
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "0uptime.cachix.org-1:ctw8yknBLg9cZBdqss+5krAem0sHYdISkw/IFdRbYdE="
      "chaotic-nyx.cachix.org-1:HfnXSw4pj95iI/n17rIDy40agHj12WfF+Gqk6SonIT8="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
      # Garnix cache (correct public key)
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
  };
  outputs = inputs @ {
    self,
    chaotic,
    lanzaboote,
    nix-flatpak,
    nixpkgs,
    sops-nix,
    ...
  }:
    with {
      locale = "en_US.UTF-8"; # select locale
      system = "x86_64-linux";
      timeZone = "Europe/Moscow";
      kexec_enabled = true;
      diffClosures = import ./modules/diff-closures.nix;
      # Nilla raw-loader compatibility: synthetic type for each input (harmless for normal flakes)
      nillaInputs = builtins.mapAttrs (_: input: input // {type = "derivation";}) inputs;
    }; let
      # Shared pre-commit hooks runner for checks and devShell
      preCommit = inputs.pre-commit-hooks.lib.${system}.run {
        src = self;
        hooks = {
          alejandra.enable = true;
          statix.enable = true;
          deadnix.enable = true;
        };
      };
    in {
      # Option docs (markdown) for base profiles, roles, and selected feature modules
      packages.${system} = let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (nixpkgs) lib;
        # DRY: evaluate module groups and generate option docs programmatically
        mkSpecialArgs = {
          inherit self inputs locale timeZone kexec_enabled pkgs;
        };
        evalMods = mods:
          lib.evalModules {
            inherit lib;
            modules = mods;
            specialArgs = mkSpecialArgs;
          };
        groups = {
          base = [
            ./modules/profiles/services.nix
            ./modules/system/profiles/security.nix
            ./modules/system/profiles/performance.nix
            ./modules/system/profiles/vm.nix
            ./modules/system/net/bridge.nix
          ];
          roles = [./modules/roles];
          games = [./modules/user/games/default.nix];
          users = [./modules/system/users.nix];
          flakePreflight = [./modules/flake-preflight.nix];
          hwAmd = [./modules/hardware/video/amd/default.nix];
          all = [./modules];
          profiles = [
            ./modules/profiles/services.nix
            ./modules/system/profiles/security.nix
            ./modules/system/profiles/performance.nix
            ./modules/system/profiles/vm.nix
            ./modules/system/profiles/aliases.nix
            ./modules/user/games/default.nix
          ];
          servers = [./modules/servers];
          hardware = [./modules/hardware];
        };
        evals = lib.mapAttrs (_: evalMods) groups;
        hasOptionsDoc = lib ? nixosOptionsDoc;
        docs = lib.optionalAttrs hasOptionsDoc (
          lib.mapAttrs (_: eval: lib.nixosOptionsDoc {inherit (eval) options;}) evals
        );
        get = name: (builtins.getAttr name docs).optionsCommonMark;
        # Discover hosts (for debugging autogen)
        hostsDir = ./hosts;
        entries = builtins.readDir hostsDir;
        hostEntries = builtins.readDir hostsDir;
        hostNames = builtins.attrNames (lib.filterAttrs (
            name: type:
              type
              == "directory"
              && (
                builtins.hasAttr "default.nix" (builtins.readDir ((builtins.toString hostsDir) + "/" + name))
              )
          )
          hostEntries);
      in
        {
          default = pkgs.zsh;
        }
        // lib.optionalAttrs hasOptionsDoc {
          # Preserve existing output names for compatibility
          options-base-md = get "base";
          options-roles-md = get "roles";
          options-games-md = get "games";
          options-users-md = get "users";
          options-flake-preflight-md = get "flakePreflight";
          options-hw-amd-md = get "hwAmd";
          options-all-md = get "all";
          options-profiles-md = get "profiles";
          options-servers-md = get "servers";
          options-hardware-md = get "hardware";

          options-md = let
            sections = [
              {
                title = "Profiles (base)";
                path = get "profiles";
              }
              {
                title = "Roles";
                path = get "roles";
              }
              {
                title = "Servers";
                path = get "servers";
              }
              {
                title = "Hardware";
                path = get "hardware";
              }
              {
                title = "Users";
                path = get "users";
              }
              {
                title = "Games";
                path = get "games";
              }
              {
                title = "Flake Preflight";
                path = get "flakePreflight";
              }
            ];
            body = builtins.concatStringsSep "\n" (
              [
                "echo \"# Options (Aggregated)\""
                "echo"
              ]
              ++ (map (s: ''
                  echo "## ${s.title}"
                  cat ${s.path} || true
                  echo
                '')
                sections)
            );
          in
            pkgs.runCommand "options.md" {} ''
              {
                ${body}
              } > $out
            '';
          # Simple index page linking to generated docs (relative names expected by scripts/gen-options.sh)
          options-index-md = let
            names = [
              "options-md"
              "options-profiles-md"
              "options-roles-md"
              "options-servers-md"
              "options-hardware-md"
              "options-users-md"
              "options-games-md"
              "options-hw-amd-md"
              "options-all-md"
              "options-base-md"
              "options-flake-preflight-md"
            ];
            toFile = n:
              if n == "options-md"
              then "options.md"
              else builtins.replaceStrings ["-md"] [".md"] n;
            lines = map (n: "- [" + n + "](./" + toFile n + ")") names;
            content = builtins.concatStringsSep "\n" ([
                "# Options Docs"
                ""
                "Index of generated option documentation artifacts:"
                ""
              ]
              ++ lines ++ [""]);
          in
            pkgs.writeText "options-index.md" content;
        };

      # Make `nix fmt` behave like in home-manager: format repo with alejandra
      formatter.${system} = let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        pkgs.writeShellApplication {
          name = "fmt";
          runtimeInputs = [pkgs.alejandra];
          text = ''
            set -euo pipefail
            alejandra -q .
          '';
        };

      # Lightweight repo checks for `nix flake check`
      checks.${system} = let
        pkgs = nixpkgs.legacyPackages.${system};
        hostsDir = ./hosts;
        entries = builtins.readDir hostsDir;
        hostNames = builtins.attrNames (nixpkgs.lib.filterAttrs (
            name: type:
              type
              == "directory"
              && (
                builtins.hasAttr "default.nix" (builtins.readDir ((builtins.toString hostsDir) + "/" + name))
              )
          )
          entries);
        hostBuildChecks = nixpkgs.lib.listToAttrs (map (name: {
            name = "build-" + name;
            value = self.nixosConfigurations.${name}.config.system.build.toplevel;
          })
          hostNames);
      in
        {
          fmt-alejandra =
            pkgs.runCommand "fmt-alejandra" {
              nativeBuildInputs = [pkgs.alejandra];
            } ''
              cd ${self}
              alejandra -q --check .
              touch "$out"
            '';

          lint-deadnix =
            pkgs.runCommand "lint-deadnix" {
              nativeBuildInputs = [pkgs.deadnix];
            } ''
              cd ${self}
              deadnix --fail .
              touch "$out"
            '';

          lint-statix =
            pkgs.runCommand "lint-statix" {
              nativeBuildInputs = [pkgs.statix];
            } ''
              cd ${self}
              statix check .
              touch "$out"
            '';
          pre-commit = preCommit;
        }
        // hostBuildChecks;

      # Developer shell
      devShells.${system}.default = let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        pkgs.mkShell {
          inherit (preCommit) shellHook;
          packages = [
            pkgs.alejandra
            pkgs.deadnix
            pkgs.statix
            pkgs.nil
            pkgs.just
            pkgs.jq
          ];
        };

      apps.${system} = let
        pkgs = nixpkgs.legacyPackages.${system};
        genOptions = pkgs.writeShellApplication {
          name = "gen-options";
          runtimeInputs = [pkgs.git pkgs.jq pkgs.nix];
          text = ''
            set -euo pipefail
            exec "${self}/scripts/gen-options.sh" "$@"
          '';
        };
        fmtApp = self.formatter.${system};
      in {
        gen-options = {
          type = "app";
          program = "${genOptions}/bin/gen-options";
        };
        fmt = {
          type = "app";
          program = "${fmtApp}/bin/fmt";
        };
      };

      nixosConfigurations = let
        lib' = nixpkgs.lib;
        pkgs = nixpkgs.legacyPackages.${system};
        commonModules = [
          ./init.nix
          nix-flatpak.nixosModules.nix-flatpak
          lanzaboote.nixosModules.lanzaboote
          chaotic.nixosModules.default
          sops-nix.nixosModules.sops
        ];
        hostsDir = ./hosts;
        entries = builtins.readDir hostsDir;
        hostNames = builtins.attrNames (lib'.filterAttrs (
            name: type:
              type
              == "directory"
              && (
                builtins.hasAttr "default.nix" (builtins.readDir ((builtins.toString hostsDir) + "/" + name))
              )
          )
          entries);
        hostExtras = name: let
          extraPath = (builtins.toString hostsDir) + "/" + name + "/extra.nix";
        in
          lib'.optional (builtins.pathExists extraPath) (/. + extraPath);
        mkHost = name:
          nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = {
              inherit locale timeZone kexec_enabled self;
              # Pass Nilla-friendly inputs (workaround for nilla-nix/nilla#14)
              inputs = nillaInputs;
            };
            modules = commonModules ++ [(import ((builtins.toString hostsDir) + "/" + name))] ++ (hostExtras name);
          };
      in
        lib'.genAttrs hostNames mkHost;
    };
}
