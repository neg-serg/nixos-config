##
# Module: nix/pgo-nix
# Purpose: put packages/nix-det-pgo — Determinate Nix 3.23.3 rebuilt with PGO and
# the five evaluation-speedup patches their tree accepts — into `nix.package`.
# That is the whole point of the package: the toplevel eval of this flake drops
# ~15 % (measured A/B, header of packages/nix-det-pgo/default.nix) without
# losing lazy-trees, because the source is still Determinate's own tree, so the
# setting table the running system relies on (lazy-trees, eval-cache,
# parallel-eval) is byte-for-byte the same one.
#
# The swap is deliberately one option and one line: `nix.package` is both the
# client on PATH and the `nix-daemon` unit's binary, and it is also the Nix that
# `nixos-rebuild` runs — so the switch that enables this restarts the daemon and
# a broken build is only recoverable from a TTY. The option description carries
# that trade-off; this module only wires it.
#
# Key options: features.nix.pgoNix.enable (default false).
# Dependencies: packages/nix-det-pgo/ (built locally, ~12 min per nix-src
# bump); the `nix-src` and `bdwgc` flake inputs it builds from.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.features.nix.pgoNix;
in
{
  config = mkIf cfg.enable {
    # modules/nix/settings.nix pins nix.package with mkForce (priority 50) to
    # Determinate's own build, so a plain definition loses to it and a second
    # mkForce conflicts with it. One step stronger (40) is what lets the flag
    # displace that definition without editing settings.nix; with the flag off
    # this module contributes nothing and settings.nix owns nix.package again,
    # which is the rollback.
    nix.package = lib.mkOverride 40 pkgs.nix-det-pgo;
  };
}
