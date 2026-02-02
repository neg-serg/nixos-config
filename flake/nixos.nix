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
    # ../modules/impurity.nix # Removed in favor of pure eval
    inputs.nix-flatpak.nixosModules.nix-flatpak
    inputs.extra-container.nixosModules.default
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.sops-nix.nixosModules.sops

    inputs.microvm.nixosModules.host
    # inputs.nyx.nixosModules.default
  ];

  hostExtras =
    name:
    let
      extraPath = (builtins.toString hostsDir) + "/" + name + "/extra.nix";
    in
    lib.optional (builtins.pathExists extraPath) (/. + extraPath);

  mkHost =
    name:
    lib.nixosSystem {
      # Use shared pkgs instance
      inherit pkgs;
      specialArgs = {
        inherit
          locale
          timeZone
          self
          inputs
          filteredSource
          ;
        iosevkaNeg = inputs.iosevka-neg.packages.${linuxSystem};

        neg = _: {
          # impurity ignored
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
          # Impurity link helper (deprecated/disabled - always pure)
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
              enabledProfiles = lib.filterAttrs (_: v: v.enable) profiles;
              sortedProfiles = lib.sort (a: b: a.id < b.id) (lib.attrValues enabledProfiles);
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
      modules =
        commonModules ++ [ (import ((builtins.toString hostsDir) + "/" + name)) ] ++ (hostExtras name);
    };
in
lib.genAttrs hostNamesEnabled mkHost
