{
  description = "Neg-Serg configuration";
  inputs = {
    bzmenu = {
      url = "github:e-tho/bzmenu";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    chaotic = {
      url = "git+https://github.com/chaotic-cx/nyx?ref=nyxpkgs-unstable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-stable.follows = "nixpkgs";
    };
    # Pin Hyprland to v0.52 using Git fetch to avoid GitHub API rate limits
    hyprland = {
      url = "git+https://github.com/hyprwm/Hyprland?ref=v0.52.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Keep selected Hyprland-related inputs in lockstep with the pinned Hyprland flake
    hyprland-protocols.follows = "hyprland/hyprland-protocols";
    # xdg-desktop-portal-hyprland is named 'xdph' in Hyprland's flake inputs (Hyprland v0.52)
    xdg-desktop-portal-hyprland.follows = "hyprland/xdph";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    iosevka-neg = {
      url = "git+ssh://git@github.com/neg-serg/iosevka-neg";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    iwmenu = {
      url = "github:e-tho/iwmenu";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nh = {
      url = "github:viperML/nh";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-qml-support = {
      url = "git+https://git.outfoxxed.me/outfoxxed/nix-qml-support";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak = {url = "github:gmodena/nix-flatpak";}; # unstable branch. Use github:gmodena/nix-flatpak/?ref=<tag> to pin releases.
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pin nixpkgs to nixos-unstable so we get Hydra cache hits
    nixpkgs = {url = "github:NixOS/nixpkgs/nixos-unstable";};
    nupm = {
      url = "github:nushell/nupm";
      flake = false;
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    raise = {
      url = "github:neg-serg/raise";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rsmetrx = {
      url = "github:neg-serg/rsmetrx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yandex-browser = {
      url = "github:miuirussia/yandex-browser.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    bzmenu,
    chaotic,
    home-manager,
    lanzaboote,
    nix-flatpak,
    nixpkgs,
    sops-nix,
    ...
  }:
    with {
      locale = "en_US.UTF-8"; # select locale
      timeZone = "Europe/Moscow";
      kexec_enabled = true;
      # Nilla raw-loader compatibility: synthetic type for each input (harmless for normal flakes)
      nillaInputs = builtins.mapAttrs (_: input: input // {type = "derivation";}) inputs;
    }; let
      # Supported systems for generic flake outputs
      supportedSystems = ["x86_64-linux" "aarch64-linux"];
      # Linux system for NixOS configurations and docs evaluation
      linuxSystem = "x86_64-linux";

      # Common lib
      inherit (nixpkgs) lib;

      # Hosts discovery shared across sections
      hostsDir = ./hosts;
      entries = builtins.readDir hostsDir;
      hostNames = builtins.attrNames (lib.filterAttrs (
          name: type:
            type
            == "directory"
            && builtins.hasAttr "default.nix" (builtins.readDir ((builtins.toString hostsDir) + "/" + name))
        )
        entries);

      # Per-system outputs factory
      perSystem = system: let
        pkgs = nixpkgs.legacyPackages.${system};
        # Pre-commit utility per system
        preCommit = inputs.pre-commit-hooks.lib.${system}.run {
          src = self;
          hooks = {
            alejandra.enable = true;
            statix.enable = true;
            deadnix.enable = true;
          };
        };

        # Documentation driver evaluated against linuxSystem to be host-agnostic
        docPkgs = nixpkgs.legacyPackages.${linuxSystem};
        nixosLib = import (docPkgs.path + "/nixos/lib") {};
        docLib =
          if nixosLib ? nixosOptionsDoc
          then nixosLib
          else lib;

        docCommonModules = [
          nix-flatpak.nixosModules.nix-flatpak
          lanzaboote.nixosModules.lanzaboote
          chaotic.nixosModules.default
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          ./modules/monitoring
        ];
        mkSpecialArgs = {
          inherit self inputs locale timeZone kexec_enabled pkgs;
        };
        evalMods = mods:
          lib.nixosSystem {
            system = linuxSystem;
            modules = docCommonModules ++ mods;
            specialArgs = mkSpecialArgs;
          };
        evalAll = evalMods [./modules];
        hasOptionsDoc = docLib ? nixosOptionsDoc;
        simpleRender = opts: let
          flatten = prefix: as:
            lib.concatLists (lib.mapAttrsToList (
                n: v: let
                  path = prefix ++ [n];
                in
                  if builtins.isAttrs v && (builtins.hasAttr "type" v)
                  then [
                    {
                      name = lib.concatStringsSep "." path;
                      desc = v.description or "";
                    }
                  ]
                  else if builtins.isAttrs v
                  then flatten path v
                  else []
              )
              as);
          items = flatten [] opts;
          lines = map (i:
            "- "
            + i.name
            + (
              if i.desc != ""
              then ": " + i.desc
              else ""
            ))
          items;
          body = lib.concatStringsSep "\n" (["# Options" ""] ++ lines ++ [""]);
        in
          pkgs.writeText "options-simple.md" body;
        docDriverAll =
          if hasOptionsDoc
          then docLib.nixosOptionsDoc {inherit (evalAll) options;}
          else {optionsCommonMark = simpleRender evalAll.options;};

        # Host build checks only for linuxSystem
        hostBuildChecks =
          lib.optionalAttrs (system == linuxSystem)
          (lib.listToAttrs (map (name: {
              name = "build-" + name;
              value = self.nixosConfigurations.${name}.config.system.build.toplevel;
            })
            hostNames));
      in {
        packages =
          # Expose NixOS host closures as packages on linuxSystem
          (lib.optionalAttrs (system == linuxSystem)
            (lib.listToAttrs (map (name: {
                inherit name;
                value = self.nixosConfigurations.${name}.config.system.build.toplevel;
              })
              hostNames)))
          // {
            default = pkgs.zsh;
            options-md = docDriverAll.optionsCommonMark;
            options-index-md = let
              names = ["options-md"];
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

        formatter = pkgs.writeShellApplication {
          name = "fmt";
          runtimeInputs = with pkgs; [
            alejandra
            black
            python3Packages.mdformat
            shfmt
            treefmt
          ];
          text = ''
            set -euo pipefail
            if git rev-parse --show-toplevel >/dev/null 2>&1; then
              repo_root="$(git rev-parse --show-toplevel)"
            else
              repo_root="${self}"
            fi
            cd "$repo_root"
            exec treefmt --config-file ${./treefmt.toml} "$@"
          '';
        };

        checks =
          {
            fmt-treefmt =
              pkgs.runCommand "fmt-treefmt" {
                nativeBuildInputs = with pkgs; [
                  alejandra
                  black
                  python3Packages.mdformat
                  shfmt
                  treefmt
                  findutils
                ];
                src = ./.;
              } ''
                set -euo pipefail
                cp -r "$src" ./src
                chmod -R u+w ./src
                cd ./src
                export XDG_CACHE_HOME="$PWD/.cache"
                mkdir -p "$XDG_CACHE_HOME"
                treefmt --config-file ${./treefmt.toml} --fail-on-change .
                touch "$out"
              '';
            lint-deadnix = pkgs.runCommand "lint-deadnix" {nativeBuildInputs = with pkgs; [deadnix];} ''
              cd ${self}
              deadnix --fail --exclude home .
              touch "$out"
            '';
            lint-statix = pkgs.runCommand "lint-statix" {nativeBuildInputs = with pkgs; [statix];} ''cd ${self}; statix check .; touch "$out"'';
            pre-commit = preCommit;
            lint-md-lang = pkgs.runCommand "lint-md-lang" {nativeBuildInputs = with pkgs; [bash coreutils findutils gnugrep gitMinimal];} ''
              set -euo pipefail
              cd ${self}
              bash scripts/check-markdown-language.sh
              : > "$out"
            '';
          }
          // hostBuildChecks;

        devShells = {
          default = pkgs.mkShell {
            inherit (preCommit) shellHook;
            packages = with pkgs; [alejandra deadnix statix nil just jq];
          };
        };

        apps = let
          genOptions = pkgs.writeShellApplication {
            name = "gen-options";
            runtimeInputs = with pkgs; [git jq nix];
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
      };
    in {
      # Per-system outputs: packages, formatter, checks, devShells, apps
      packages = lib.genAttrs supportedSystems (s: (perSystem s).packages);
      formatter = lib.genAttrs supportedSystems (s: (perSystem s).formatter);
      checks = lib.genAttrs supportedSystems (s: (perSystem s).checks);
      devShells = lib.genAttrs supportedSystems (s: (perSystem s).devShells);
      apps = lib.genAttrs supportedSystems (s: (perSystem s).apps);

      # NixOS configurations (linuxSystem only)
      nixosConfigurations = let
        commonModules = [
          ./init.nix
          nix-flatpak.nixosModules.nix-flatpak
          lanzaboote.nixosModules.lanzaboote
          chaotic.nixosModules.default
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
        ];
        hostExtras = name: let
          extraPath = (builtins.toString hostsDir) + "/" + name + "/extra.nix";
        in
          lib.optional (builtins.pathExists extraPath) (/. + extraPath);
        mkHost = name:
          lib.nixosSystem {
            system = linuxSystem;
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
