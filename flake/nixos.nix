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
  hostNamesEnabled = [ "telfir" ];

  linuxSystem = "x86_64-linux";
  locale = "en_US.UTF-8";
  timeZone = "Europe/Moscow";

  commonModules = [
    ../init.nix
    inputs.determinate.nixosModules.default
    inputs.sops-nix.nixosModules.sops
  ];

  hostExtras =
    name:
    let
      extraPath = (builtins.toString hostsDir) + "/" + name + "/extra.nix";
    in
    lib.optional (builtins.pathExists extraPath) (/. + extraPath);

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

  mkHost =
    name:
    lib.nixosSystem {
      inherit pkgs;
      specialArgs = mkSpecialArgs;
      modules =
        commonModules ++ [ (import ((builtins.toString hostsDir) + "/" + name)) ] ++ (hostExtras name);
    };

  # A/B test configurations: same base host but WITH ONLY THE TEST PROFILE ACTIVE.
  # This replaces the base profiles entirely (via mkForce) so the comparison is clean:
  # base config vs single-profile test config, no priority conflicts.
  # NEVER evaluated during normal `nixos-rebuild switch --flake .#telfir`.
  # Build explicitly: nixos-rebuild switch --flake '.#telfir-lite'
  mkTestHost =
    baseName: testProfile:
    lib.nixosSystem {
      inherit pkgs;
      specialArgs = mkSpecialArgs;
      modules = commonModules
        ++ [ (import ((builtins.toString hostsDir) + "/" + baseName)) ]
        ++ (hostExtras baseName)
        ++ [
          # mkForce: replace host profiles entirely so the test profile is the sole active one
          { features.profiles = lib.mkForce [ testProfile ]; }
        ];
    };

  # Predefined A/B test configurations.
  testProfiles = [
    "gaming"
    "audio-pro"
    "lite"
    "server"
  ];

  # Keys like "telfir-gaming", "telfir-audio-pro", etc.
  prefixedTestConfigs = lib.listToAttrs (map (p: {
    name = "telfir-${p}";
    value = mkTestHost "telfir" p;
  }) testProfiles);

in
lib.genAttrs hostNamesEnabled mkHost // prefixedTestConfigs
