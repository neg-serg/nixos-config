{
  description = "Neg-Serg configuration";
  inputs = {
    chaotic = {url = "git+https://github.com/chaotic-cx/nyx?ref=nyxpkgs-unstable"; inputs.nixpkgs.follows = "nixpkgs";};
    # Pin Hyprland to v0.51 using Git fetch to avoid GitHub API rate limits
    hyprland = {url = "git+https://github.com/hyprwm/Hyprland?ref=v0.51.0"; inputs.nixpkgs.follows = "nixpkgs";};
    # Keep Hyprland-related inputs in lockstep with the pinned Hyprland flake
    hyprland-protocols.follows = "hyprland/hyprland-protocols";
    hyprland-qtutils.follows = "hyprland/hyprland-qtutils";
    # qt-support is nested under hyprland-qtutils
    hyprland-qt-support.follows = "hyprland/hyprland-qtutils/hyprland-qt-support";
    # xdg-desktop-portal-hyprland is named 'xdph' in Hyprland's flake inputs
    xdg-desktop-portal-hyprland.follows = "hyprland/xdph";
    lanzaboote = {url = "github:nix-community/lanzaboote"; inputs.nixpkgs.follows = "nixpkgs";};
    nh = {url = "github:viperML/nh"; inputs.nixpkgs.follows = "nixpkgs";};
    nix-flatpak = {url = "github:gmodena/nix-flatpak";}; # unstable branch. Use github:gmodena/nix-flatpak/?ref=<tag> to pin releases.
    nix-gaming = {url = "github:fufexan/nix-gaming"; inputs.nixpkgs.follows = "nixpkgs";};
    # Pin nixpkgs to nixos-unstable so we get Hydra cache hits
    nixpkgs = {url = "github:NixOS/nixpkgs/nixos-unstable";};
    raise = {url = "github:neg-serg/raise"; inputs.nixpkgs.follows = "nixpkgs";};
    sops-nix = {url = "github:Mic92/sops-nix"; inputs.nixpkgs.follows = "nixpkgs";};
    pre-commit-hooks = {url = "github:cachix/git-hooks.nix"; inputs.nixpkgs.follows = "nixpkgs";};
    
  };

  # Make Cachix caches available to all `nix {build,develop,run}` commands
  # Note: nixConfig must be a literal attrset (cannot import).
  nixConfig = {
    extra-substituters = [
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
    extra-trusted-public-keys = [
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
      "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA"
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
      # Nilla raw-loader compatibility: synthetic type for each input (harmless for normal flakes)
      nillaInputs = builtins.mapAttrs (_: input: input // {type = "derivation";}) inputs;
    }; let
      # Hosts discovery shared across sections
      hostsDir = ./hosts;
      entries = builtins.readDir hostsDir;
      hostNames = builtins.attrNames (nixpkgs.lib.filterAttrs (
        name: type:
          type == "directory"
          && builtins.hasAttr "default.nix" (builtins.readDir ((builtins.toString hostsDir) + "/" + name))
      ) entries);

      # Common pkgs/lib
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      # Shared pre-commit hooks runner for checks and devShell
      preCommit = inputs.pre-commit-hooks.lib.${system}.run { src = self; hooks = { alejandra.enable = true; statix.enable = true; deadnix.enable = true; }; };
    in {
      # Option docs (markdown) for base profiles, roles, and selected feature modules
      packages.${system} = let
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
        # Prefer NixOS lib (has nixosOptionsDoc) from the pinned nixpkgs path
        nixosLib = import (pkgs.path + "/nixos/lib") {};
        docLib = if nixosLib ? nixosOptionsDoc then nixosLib else (if lib ? nixosOptionsDoc then lib else pkgs.lib);
        hasOptionsDoc = docLib ? nixosOptionsDoc;
        docs = lib.optionalAttrs hasOptionsDoc (
          lib.mapAttrs (_: eval: docLib.nixosOptionsDoc {inherit (eval) options;}) evals
        );
        get = name: (builtins.getAttr name docs).optionsCommonMark;
        # Map group keys to output slugs and generate per-doc outputs
        docNames = [
          { key = "base";           slug = "base"; }
          { key = "roles";          slug = "roles"; }
          { key = "games";          slug = "games"; }
          { key = "users";          slug = "users"; }
          { key = "flakePreflight"; slug = "flake-preflight"; }
          { key = "hwAmd";          slug = "hw-amd"; }
          { key = "all";            slug = "all"; }
          { key = "profiles";       slug = "profiles"; }
          { key = "servers";        slug = "servers"; }
          { key = "hardware";       slug = "hardware"; }
        ];
        perDocOutputs = lib.listToAttrs (map (d: {
          name = "options-${d.slug}-md";
          value = get d.key;
        }) docNames);
        # (removed stale host discovery: not used in docs)
      in
        {
          default = pkgs.zsh;
        }
        // lib.optionalAttrs hasOptionsDoc (
          perDocOutputs
          // {
            options-md = let
              titlesByKey = {
                profiles = "Profiles (base)";
                roles = "Roles";
                servers = "Servers";
                hardware = "Hardware";
                users = "Users";
                games = "Games";
                flakePreflight = "Flake Preflight";
              };
              aggregateKeys = ["profiles" "roles" "servers" "hardware" "users" "games" "flakePreflight"];
              body = builtins.concatStringsSep "\n" (
                [
                  "echo \"# Options (Aggregated)\""
                  "echo"
                ] ++ (map (name: ''
                  echo "## ${builtins.getAttr name titlesByKey}"
                  cat ${get name} || true
                  echo
                '') aggregateKeys)
              );
            in pkgs.runCommand "options.md" {} ''
              {
                ${body}
              } > $out
            '';
            # Simple index page linking to generated docs (relative names expected by scripts/gen-options.sh)
            options-index-md = let
              names = ["options-md"] ++ (map (d: "options-${d.slug}-md") docNames);
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
              ] ++ lines ++ [""]);
            in pkgs.writeText "options-index.md" content;
          }
        );

      # Make `nix fmt` behave like in home-manager: format repo with alejandra
      formatter.${system} =
        pkgs.writeShellApplication {
          name = "fmt";
          runtimeInputs = with pkgs; [ alejandra ];
          text = ''
            set -euo pipefail
            alejandra -q .
          '';
        };

      # Lightweight repo checks for `nix flake check`
      checks.${system} = let
        hostBuildChecks = lib.listToAttrs (map (name: {
            name = "build-" + name;
            value = self.nixosConfigurations.${name}.config.system.build.toplevel;
          })
          hostNames);
      in
        {
          fmt-alejandra = pkgs.runCommand "fmt-alejandra" { nativeBuildInputs = with pkgs; [ alejandra ]; } ''cd ${self}; alejandra -q --check .; touch "$out"'';
          lint-deadnix = pkgs.runCommand "lint-deadnix" { nativeBuildInputs = with pkgs; [ deadnix ]; } ''cd ${self}; deadnix --fail .; touch "$out"'';
          lint-statix = pkgs.runCommand "lint-statix" { nativeBuildInputs = with pkgs; [ statix ]; } ''cd ${self}; statix check .; touch "$out"'';
          pre-commit = preCommit;
          lint-md-lang = pkgs.runCommand "lint-md-lang" { nativeBuildInputs = with pkgs; [ bash coreutils findutils gnugrep gitMinimal ]; } ''
            set -euo pipefail
            cd ${self}
            bash scripts/check-markdown-language.sh
            : > "$out"
          '';
        }
        // hostBuildChecks;

      # Developer shell
      devShells.${system}.default = pkgs.mkShell {
        inherit (preCommit) shellHook;
        packages = with pkgs; [ alejandra deadnix statix nil just jq ];
      };

      apps.${system} = let
        genOptions = pkgs.writeShellApplication {
          name = "gen-options";
          runtimeInputs = with pkgs; [ git jq nix ];
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
        commonModules = [
          ./init.nix
          nix-flatpak.nixosModules.nix-flatpak
          lanzaboote.nixosModules.lanzaboote
          chaotic.nixosModules.default
          sops-nix.nixosModules.sops
        ];
        hostExtras = name: let
          extraPath = (builtins.toString hostsDir) + "/" + name + "/extra.nix";
        in
          lib.optional (builtins.pathExists extraPath) (/. + extraPath);
        mkHost = name: lib.nixosSystem {
            inherit system;
            specialArgs = {
              inherit locale timeZone kexec_enabled self;
              # Pass Nilla-friendly inputs (workaround for nilla-nix/nilla#14)
              inputs = nillaInputs;
            };
            modules = commonModules ++ [(import ((builtins.toString hostsDir) + "/" + name))] ++ (hostExtras name);
          };
      in
        lib.genAttrs hostNames mkHost;
    };
}
