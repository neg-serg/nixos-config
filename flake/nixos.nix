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
          mkHomeFiles = files:
            let
              inherit (lib)
                filterAttrs
                mapAttrs'
                mapAttrsToList
                nameValuePair
                hasPrefix
                removePrefix
                ;

              # Separate impure links from regular files
              isImpure = _: v: v ? IsImpure && v.IsImpure;
              impureFiles = filterAttrs isImpure files;
              regularFiles = filterAttrs (n: v: !isImpure n v) files;

              # Generate systemd tmpfiles rules for impure links
              # Format: L+ /home/user/path - - - - /etc/nixos/path
              mkTmpfiles =
                path: cfg:
                let
                  # Handle path normalization (remove leading slash or ./ )
                  destRel = removePrefix "./" path;
                  homePath = "%h/" + destRel; # %h is systemd specifier for Home Directory
                in
                "L+ ${homePath} - - - - ${cfg.Path}";
            in
            {
              users.users.neg.maid.file.home = regularFiles;
              systemd.user.tmpfiles.rules = mapAttrsToList mkTmpfiles impureFiles;
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
          # Impurity link helper
          # Calculates the path relative to the repo root (/etc/nixos) based on the inputs.self store path
          linkImpure =
            path:
            let
              pathStr = toString path;
              selfStr = toString self;
              # Remove the store path prefix of the flake source to get the relative path
              relPath = lib.removePrefix (selfStr + "/") pathStr;
              # Hardcoded repo root as per user context
              repoRoot = "/etc/nixos";
            in
            {
              IsImpure = true;
              Path = "${repoRoot}/${relPath}";
            };

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
