let
  # Keep these literal to satisfy flake nixConfig (cannot be thunks)
  extraSubstituters = [
    "https://nix-community.cachix.org"
    "https://hyprland.cachix.org"
    # Additional popular caches
    "https://numtide.cachix.org"
    "https://nixpkgs-wayland.cachix.org"
    "https://hercules-ci.cachix.org"
    "https://cuda-maintainers.cachix.org"
    "https://nix-gaming.cachix.org"
    # Personal cache
    "https://neg-serg.cachix.org"
  ];
  extraTrustedKeys = [
    # nix-community
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    # Hyprland
    "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    # numtide
    "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
    # nixpkgs-wayland
    "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
    # hercules-ci
    "hercules-ci.cachix.org-1:ZZeDl9Va+xe9j+KqdzoBZMFJHVQ42Uu/c/1/KMC5Lw0="
    # cuda-maintainers
    "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    # nix-gaming
    "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
    # personal cache
    "neg-serg.cachix.org-1:MZ+xYOrDj1Uhq8GTJAg//KrS4fAPpnIvaWU/w3Qz/wo="
  ];
in {
  description = "Home Manager configuration of neg";
  # Global Nix configuration for this flake (affects local and CI when respected)
  # Single source of truth for caches; Home Manager modules receive these via mkHMArgs.caches
  nixConfig = {
    experimental-features = ["nix-command" "flakes"];
    # Keep literal lists here to avoid early-import pitfalls; modules reuse these values via mkHMArgs
    extra-substituters = extraSubstituters;
    extra-trusted-public-keys = extraTrustedKeys;
  };
  inputs = {
    bzmenu = {
      url = "github:e-tho/bzmenu";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    chaotic = {
      url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pin hy3 to release compatible with Hyprland v0.51.x
    hy3 = {
      url = "git+https://github.com/outfoxxed/hy3?ref=hl0.51.0";
      inputs.hyprland.follows = "hyprland";
    };
    # Pin Hyprland to the same release train used by the system flake
    hyprland = {
      url = "git+https://github.com/hyprwm/Hyprland?ref=v0.52.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-protocols.follows = "hyprland/hyprland-protocols";
    xdg-desktop-portal-hyprland.follows = "hyprland/xdph";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # CamelCase alias for convenience in code
    homeManagerInput.follows = "home-manager";
    iosevka-neg = {
      url = "git+ssh://git@github.com/neg-serg/iosevka-neg";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # CamelCase alias for convenience in code
    iosevkaNegInput.follows = "iosevka-neg";
    iwmenu = {
      url = "github:e-tho/iwmenu";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Nushell package manager (non-flake repo) to avoid vendoring sources
    nupm = {
      url = "github:nushell/nupm";
      flake = false;
    };
    # Track nixos-unstable to receive latest packages (Floorp, etc.)
    nixpkgs = {url = "github:NixOS/nixpkgs/nixos-unstable";};
    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
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
    # CamelCase alias for convenience in code
    sopsNixInput.follows = "sops-nix";
    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # CamelCase alias for convenience in code
    stylixInput.follows = "stylix";
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yandex-browser = {
      url = "github:miuirussia/yandex-browser.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # CamelCase alias for convenience in code
    yandexBrowserInput.follows = "yandex-browser";
    # Rust window raiser utility used in Hyprland bindings
    raise = {
      url = "github:neg-serg/raise";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    chaotic,
    homeManagerInput,
    iosevkaNegInput,
    nixpkgs,
    nur,
    sopsNixInput,
    stylixInput,
    yandexBrowserInput,
    ...
  }: let
    inherit (nixpkgs) lib;
    # Helpers for environment parsing (DRY)
    boolEnv = name: let v = builtins.getEnv name; in v == "1" || v == "true" || v == "yes";
    splitEnvList = name: let
      v = builtins.getEnv name;
    in
      if v == ""
      then []
      else (lib.filter (s: s != "") (lib.splitString "," v));
    # Prefer evaluating only one system by default to speed up local eval.
    # You can override the systems list for CI or cross builds by setting
    # HM_SYSTEMS to a comma-separated list (e.g., "x86_64-linux,aarch64-linux").
    defaultSystem = "x86_64-linux";
    systems = let
      fromEnv = splitEnvList "HM_SYSTEMS";
      cleaned = lib.unique fromEnv;
    in
      if cleaned == []
      then [defaultSystem]
      else cleaned;

    # Pass only minimal inputs required by HM modules (nupm for Nushell).
    # Nilla raw-loader compatibility: add a synthetic type to each selected input.
    hmInputs =
      builtins.mapAttrs (_: input: input // {type = "derivation";}) {
        inherit (inputs) nupm;
      };

    # Common Home Manager building blocks
    hmHelpers = import ./flake/hm-helpers.nix {
      inherit lib stylixInput chaotic sopsNixInput;
    };
    inherit (hmHelpers) hmBaseModules;

    # mkHMArgs moved to a helper; keep semantics identical
    mkHMArgs = import ./flake/mkHMArgs.nix {
      inherit lib perSystem yandexBrowserInput nur inputs;
      inherit hmInputs extraSubstituters extraTrustedKeys;
    };

    # Build per-system attributes in one place
    perSystem = lib.genAttrs systems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (import ../packages/overlay.nix)
            (_: prev: let
              inherit (prev.stdenv.hostPlatform) system;
            in {
              inherit (inputs.hyprland.packages.${system}) hyprland;
              inherit (inputs.xdg-desktop-portal-hyprland.packages.${system}) xdg-desktop-portal-hyprland;
              hyprlandPlugins =
                prev.hyprlandPlugins
                // {
                  hy3 = inputs.hy3.packages.${system}.hy3;
                };
            })
          ]; # local packages overlay under pkgs.neg.* (no global NUR overlay)
          config = {
            allowAliases = false;
          };
        };
        # Avoid fetching private iosevka-neg on CI providers (GitHub Actions, Garnix).
        # Policy:
        #   - If HM_USE_IOSEVKA_NEG is truthy => always use private.
        #   - Else if we're in CI (CI/GITHUB_ACTIONS/GARNIX/GARNIX_CI set) => use public fallback.
        #   - Else (local dev) => use private.
        # Modules access `iosevkaNeg.nerd-font`, so mirror that shape when falling back.
        iosevkaNeg = let
          boolEnv = name: let v = builtins.getEnv name; in v == "1" || v == "true" || v == "yes";
          hmUse = boolEnv "HM_USE_IOSEVKA_NEG";
          g = builtins.getEnv;
          isCI = (g "CI" != "") || (g "GITHUB_ACTIONS" != "") || (g "GARNIX" != "") || (g "GARNIX_CI" != "");
          usePrivate =
            if hmUse
            then true
            else if isCI
            then false
            else true;
        in
          if usePrivate
          then iosevkaNegInput.packages.${system}
          else {nerd-font = pkgs.nerd-fonts.iosevka;};
        # NUR is accessed lazily via faProvider in mkHMArgs only when needed.

        # Common toolsets for devShells to avoid duplication
        devTools = import ./flake/devtools.nix {inherit lib pkgs;};
        inherit (devTools) devNixTools rustBaseTools rustExtraTools;
      in {
        inherit pkgs iosevkaNeg;

        devShells = import ./flake/devshells.nix {
          inherit pkgs rustBaseTools rustExtraTools devNixTools;
        };

        packages = let
          extrasFlag = boolEnv "HM_EXTRAS";
          extrasSet = import ../packages/flake/extras.nix {inherit pkgs;};
          customPkgs = import ../packages/flake/custom-packages.nix {inherit pkgs;};
        in
          ({default = pkgs.zsh;} // customPkgs)
          // lib.optionalAttrs extrasFlag extrasSet;

        # Checks: fail if formatting or linters would change files
        checks = import ./flake/checks.nix {
          inherit pkgs self system;
        };
      }
    );
    # Use defaultSystem for user HM configs
  in {
    # Gate devShells under HM_EXTRAS; always keep defaultSystem for local dev.
    # This reduces multi-system eval noise in CI unless explicitly requested.
    devShells = let
      extras = boolEnv "HM_EXTRAS";
      sysList =
        if extras
        then systems
        else [defaultSystem];
    in
      lib.genAttrs sysList (s: perSystem.${s}.devShells);
    packages = lib.genAttrs systems (s: perSystem.${s}.packages);
    # Docs outputs are gated by HM_DOCS env; heavy HM evals are skipped by default.
    docs = import ./flake/docs.nix {
      inherit lib perSystem systems homeManagerInput mkHMArgs hmBaseModules boolEnv;
    };
    checks = import ./flake/checks-outputs.nix {
      inherit lib systems defaultSystem perSystem splitEnvList boolEnv homeManagerInput mkHMArgs hmBaseModules self;
    };

    homeConfigurations = lib.genAttrs ["neg" "neg-lite"] (
      n:
        homeManagerInput.lib.homeManagerConfiguration {
          inherit (perSystem.${defaultSystem}) pkgs;
          extraSpecialArgs = mkHMArgs defaultSystem;
          modules = hmBaseModules (lib.optionalAttrs (n == "neg-lite") {profile = "lite";});
        }
    );

    # Reusable project templates
    templates = import ./flake/templates.nix;
  };
}
