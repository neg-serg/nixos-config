{
  inputs,
  nixpkgs,
  self,
  ...
}: let
  inherit (nixpkgs) lib;
  hostsDir = ../hosts;
  entries = builtins.readDir hostsDir;
  hostNames = builtins.attrNames (lib.filterAttrs (
      name: type:
        type
        == "directory"
        && builtins.hasAttr "default.nix" (builtins.readDir ((builtins.toString hostsDir) + "/" + name))
    )
    entries);
  hostNamesEnabled = lib.filter (name: name != "telfir-vm") hostNames;

  linuxSystem = "x86_64-linux";
  locale = "en_US.UTF-8";
  timeZone = "Europe/Moscow";

  # Nilla raw-loader compatibility
  nillaInputs = builtins.mapAttrs (_: input: input // {type = "derivation";}) inputs;

  commonModules = [
    ../init.nix
    ../modules/impurity.nix
    inputs.nix-flatpak.nixosModules.nix-flatpak
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.sops-nix.nixosModules.sops

    inputs.nvf.nixosModules.default
  ];

  hostExtras = name: let
    extraPath = (builtins.toString hostsDir) + "/" + name + "/extra.nix";
  in
    lib.optional (builtins.pathExists extraPath) (/. + extraPath);

  mkHost = name:
    lib.nixosSystem {
      system = linuxSystem;
      specialArgs = {
        inherit locale timeZone self;
        inputs = nillaInputs;
        iosevkaNeg = inputs.iosevka-neg.packages.${linuxSystem};
      };
      modules = commonModules ++ [(import ((builtins.toString hostsDir) + "/" + name))] ++ (hostExtras name);
    };
in
  lib.genAttrs hostNamesEnabled mkHost
