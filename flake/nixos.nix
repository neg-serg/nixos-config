{
  inputs,
  nixpkgs,
  self,
  pkgs,
  filteredSource,
  ...
}:
let
  inherit (nixpkgs) lib;
  hostsDir = ../hosts;

  linuxSystem = "x86_64-linux";
  locale = "en_US.UTF-8";
  timeZone = "Europe/Moscow";

  commonModules = [
    ../init.nix
    inputs.determinate.nixosModules.default
    inputs.nix-flatpak.nixosModules.nix-flatpak
    inputs.sops-nix.nixosModules.sops
    ../modules/system/disabled-modules.nix
  ];

  hostExtras =
    name:
    lib.optional (builtins.pathExists (hostsDir + "/" + name + "/extra.nix")) (
      hostsDir + "/" + name + "/extra.nix"
    );

  # -------------------------------------------------------------------------
  # Domain filter — enables parallel eval by skipping unused module domains.
  # Each domain maps to a subdirectory under modules/. The filter
  # `domainFilter :: string -> bool` is passed via specialArgs to every module.
  # modules/default.nix uses it to conditionally import domain aggregators.
  # -------------------------------------------------------------------------

  # Core: always needed (feature flags, profiles, roles, security, system foundation).
  coreDomains = [
    "core"
    "features"
    "profiles"
    "roles"
    "nix"
    "security"
    "secrets"
    "shell"
    "system"
    "hardware"
    "monitoring"
    "flake-preflight"
    "diff-closures"
  ];

  # Basic: core + CLI / text-mode tools. Enough for a minimal interactive system.
  basicDomains = coreDomains ++ [
    "cli"
    "tools"
    "text"
    "fonts"
    "documentation"
  ];

  # Lite: basic + SSH server. No GUI, no desktop apps.
  liteDomains = basicDomains ++ [ "servers" ];

  # Server: lite + service management + monitoring. Headless server profile.
  serverDomains = basicDomains ++ [
    "servers"
  ];

  # Full desktop: everything imported (current default).
  allDomains = basicDomains ++ [
    "appimage"
    "apps"
    "dev"
    "emulators"
    "flatpak"
    "fun"
    "games"
    "llm"
    "media"
    "servers"
    "torrent"
    "user"
    "web"
  ];

  # Odin: full desktop minus domains with zero odin references.
  # Excluded: appimage (no odin usage), apps (obsidian via flatpak),
  #           llm (ollama disabled), web (empty module).
  odinDomains = basicDomains ++ [
    "dev"
    "emulators"
    "flatpak"
    "fun"
    "games"
    "media"
    "servers"
    "torrent"
    "user"
  ];

  mkDomainFilter = domains: name: builtins.elem name domains;

  # Shared specialArgs for all NixOS configurations.
  mkSpecialArgs = {
    inherit
      locale
      timeZone
      self
      inputs
      filteredSource
      ;
    iosevkaNeg = inputs.iosevka-neg.packages.${linuxSystem};
    goldfish = inputs.goldfish.packages.${linuxSystem}.goldfish;

    # Default: import all domains (full workstation).
    domainFilter = mkDomainFilter allDomains;
    opts = import (self + "/lib/opts.nix") { inherit lib; };

    neg = {
      # Core structural helpers (no config dependency)
      mkHomeFiles = files: {
        users.users.neg.maid.file.home = files;
      };
      mkXdgText = path: text: {
        home."${path}".text = text;
      };
      mkLocalBin = name: text: {
        home.".local/bin/${name}" = {
          inherit text;
          executable = true;
        };
      };
      linkImpure = x: x;

      # Browser helpers
      mkUserJs =
        prefs:
        lib.concatStrings (
          lib.mapAttrsToList (name: value: ''
            user_pref("${name}", ${builtins.toJSON value});
          '') prefs
        );
      mkProfilesIni =
        profiles:
        let
          sortedProfiles =
            profiles
            |> lib.filterAttrs (_: v: v.enable)
            |> lib.attrValues
            |> lib.sort (a: b: a.id < b.id);
          mkSection = index: profile: ''
            [Profile${toString index}]
            Name=${profile.name}
            Path=${profile.path}
            IsRelative=1
            Default=${if profile.isDefault then "1" else "0"}
          '';
          sections = lib.imap0 mkSection sortedProfiles;
        in
        ''
          [General]
          StartWithLastProfile=1
          Version=2

          ${lib.concatStringsSep "\n" sections}
        '';
    };
  };

  # Profile → domain filter map. Key = test profile name, value = domain list.
  profileDomainSets = {
    lite = liteDomains;
    server = serverDomains;
    # gaming / audio-pro / desktop: use allDomains (full GUI stack).
  };

  mkTestSpecialArgs =
    testProfile:
    let
      domains = profileDomainSets.${testProfile} or allDomains;
    in
    mkSpecialArgs
    // {
      domainFilter = mkDomainFilter domains;
    };

  mkHost =
    name:
    lib.nixosSystem {
      inherit pkgs;
      specialArgs = mkSpecialArgs // {
        domainFilter = mkDomainFilter (if name == "odin" then odinDomains else allDomains);
      };
      modules =
        commonModules ++ [ (import ((builtins.toString hostsDir) + "/" + name)) ] ++ (hostExtras name);
    };

  # A/B test configurations: same base host but WITH ONLY THE TEST PROFILE ACTIVE.
  # This replaces the base profiles entirely (via mkForce) so the comparison is clean:
  # base config vs single-profile test config, no priority conflicts.
  #
  # Parallel-eval refactoring (Jul 2026): each test config uses a restrictive
  # domainFilter (liteDomains / serverDomains) to skip importing unused module
  # domains (GUI, nix-maid, games, etc.), producing smaller eval trees for
  # nix-eval-jobs to process in parallel.
  #
  # NEVER evaluated during normal `nixos-rebuild switch --flake .#odin`.
  # Build explicitly: nixos-rebuild switch --flake '.#odin-lite'
  mkTestHost =
    baseName: testProfile:
    lib.nixosSystem {
      inherit pkgs;
      specialArgs = mkTestSpecialArgs testProfile;
      modules =
        commonModules
        ++ [ (import ((builtins.toString hostsDir) + "/" + baseName)) ]
        ++ (hostExtras baseName)
        ++ [
          # mkForce: replace host profiles entirely so the test profile is the sole active one
          { features.profiles = lib.mkForce [ testProfile ]; }
          # Test profile compat: provide stubs for users/features that the
          # restricted domain filter would otherwise leave unconfigured.
          # lite/server profiles skip "user" and "flatpak" domains,
          # so greetd's greeter and nix-flatpak's user assertions fail.
          ({ config, lib, ... }: {
            config = lib.mkMerge [
              (lib.mkIf (!config.features.gui.enable) {
                features.gui.vicinae.enable = lib.mkForce false;
              })
              {
                users.users.greeter = {
                  isSystemUser = lib.mkDefault true;
                  group = lib.mkDefault "greeter";
                };
                users.groups.greeter = { };
                users.users.flatpak = {
                  isSystemUser = lib.mkDefault true;
                  group = lib.mkDefault "flatpak";
                };
                users.groups.flatpak = { };
              }
            ];
          })
        ];
    };

  # Predefined A/B test configurations.
  testProfiles = [
    "gaming"
    "audio-pro"
    "lite"
    "server"
  ];

  # Keys like "odin-gaming", "odin-audio-pro", etc.
  prefixedTestConfigs = lib.listToAttrs (
    map (p: {
      name = "odin-${p}";
      value = mkTestHost "odin" p;
    }) testProfiles
  );

in
{
  odin = mkHost "odin";
}
// prefixedTestConfigs
// {
  inherit mkTestHost testProfiles;
}
