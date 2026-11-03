# Declarative nix-cache-pin pins for this repository.
#
# nix-cache-pin ships a flake-parts module, but this flake is not flake-parts
# based, so the module is not imported. This file mirrors the module's JSON
# contract instead: every pin below becomes a JSON config plus a
# `nix run .#cache-pin-<name>` app (and `.#cache-pin` for all pins at once).
#
# The CLI edits ./flake.nix of the flake it runs in and re-locks the input, so
# run the apps from the repository root. Use `--dry-run` first: it searches and
# prints the revision without writing anything.
{
  inputs,
  pkgs,
  system,
}:
let
  inherit (pkgs) lib;

  # Defaults copied from the upstream flake-parts module. PinConfig has no serde
  # default for most fields, so every one of them must be present in the JSON.
  defaults = {
    wishPackages = [ ];
    consumerFlakeRef = null;
    consumerTargets = { };
    requiredConsumerTargets = { };
    depth = 15;
    branchFallbacks = [ ];
    failFast = false;
    lockOnly = false;
    verifyClosure = false;
    versionConstraints = { };
    arch = system;
  };

  pins = {
    # CachyOS kernel input. Upstream dropped the preset's cache list after the
    # Lantian host was compromised (xddxdd/nix-cachyos-kernel#110) and restored
    # it under a new URL, so the cache is listed explicitly here. Hydra only
    # reports build status; the cache above is what store paths are trusted from.
    cachyos = {
      packages = [ "linux-cachyos-latest-lto-x86_64-v3" ];
      inputName = "nix-cachyos-kernel";
      attrPrefix = "";
      pythonPackages = null;
      caches = [ "https://cache.lantian.pub/lantian" ];
      hydraJobset = "lantian/nix-cachyos-kernel";
      hydraUrl = "https://hydra.lantian.pub";
      hydraJobPattern = "{jobset}/packages.{arch}.{pkg}";
      hydraRevInput = "flake";
      branch = "release";
      branchFallbacks = [ "master" ];
      flakeRef = "github:xddxdd/nix-cachyos-kernel";
      flakeOutput = "packages";
    };
  };

  configFor =
    name: pin:
    pkgs.writeText "cache-pin-${name}.json" (builtins.toJSON (defaults // pin // { inherit name; }));

  binaries = inputs.nix-cache-pin.packages.${system}.all-binaries;
  # The CLI shells out to `nix flake lock`/`nix eval` and Git.
  runtimePath = lib.makeBinPath [
    pkgs.nix
    pkgs.git
  ];

  mkPinApp =
    name: pin:
    pkgs.writeShellScriptBin "cache-pin-${name}" ''
      export PATH="${runtimePath}:$PATH"
      exec ${binaries}/bin/cache-pin --config ${configFor name pin} "$@"
    '';

  configArgs = lib.concatStringsSep " " (
    lib.mapAttrsToList (name: pin: "--config ${configFor name pin}") pins
  );
  allApp = pkgs.writeShellScriptBin "cache-pin" ''
    export PATH="${runtimePath}:$PATH"
    exec ${binaries}/bin/cache-pin ${configArgs} "$@"
  '';
in
{
  apps =
    (lib.mapAttrs' (
      name: pin:
      lib.nameValuePair "cache-pin-${name}" {
        type = "app";
        program = "${mkPinApp name pin}/bin/cache-pin-${name}";
      }
    ) pins)
    // {
      cache-pin = {
        type = "app";
        program = "${allApp}/bin/cache-pin";
      };
    };
}
