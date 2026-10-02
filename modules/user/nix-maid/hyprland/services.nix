{
  lib,
  pkgs,
  inputs,
  neg,
  repoRoot,
  ...
}:
let
  # Module-shaped systemd user units (lib/systemd-user.nix). This file is a
  # plain fragment imported by main.nix (no `config` in scope), so build the
  # helper from the same specialArg neg.nix uses.
  systemdUser = neg.systemdUser lib;

  # The helper scripts and the package list live in ./services/compositor-helpers.nix;
  # the unit definitions are split by theme into the other ./services/*.nix files.
  helpers = import ./services/compositor-helpers.nix {
    inherit
      lib
      pkgs
      inputs
      neg
      repoRoot
      ;
  };

  # main.nix imports this file as a plain fragment
  # (`services = import ./services.nix { … }`), not as a NixOS module, so
  # `imports = neg.importDir { … }` does not apply: import every themed sibling
  # and merge the attrsets they return.
  unitArgs = {
    inherit
      lib
      pkgs
      inputs
      neg
      repoRoot
      systemdUser
      ;
  }
  // helpers.helpers;

  units = map (path: import path unitArgs) (
    neg.importDir {
      dir = ./services;
      exclude = [ "compositor-helpers.nix" ];
    }
  );
in
{
  inherit (helpers) packages;

  systemdTargets = lib.mergeAttrsList (map (m: m.systemdTargets or { }) units);
  systemdServices = lib.mergeAttrsList (map (m: m.systemdServices or { }) units);
}
