{ lib, mkBool, ... }:
{
  options.features = {
    # NOTE: `features.profile` (singular) removed — was dead code.
    # Use `features.profiles` (plural, list) for profile composition.

    # Development-speed mode: aggressively trim heavy features/inputs for faster local iteration
    devSpeed.enable = mkBool "enable dev-speed mode (trim heavy features for faster eval)" false;

    # Distributed builds: hand builds to a second x86_64 machine over SSH
    # (modules/nix/distributed-build.nix). Default off — no working builder host
    # exists yet; the module header records what was already ruled out.
    nix.remoteBuilder.enable = mkBool "send builds to a remote x86_64 builder over SSH" false;

    # PGO build of Determinate Nix (packages/nix-det-pgo/): the same 3.23.3
    # source the host already runs, rebuilt with a profile trained on this
    # repo's own evaluation plus the five eval-speedup patches it accepts.
    # Measured -18 % on the toplevel drvPath eval, same drvPath out.
    nix.pgoNix.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Swap `nix.package` for the PGO + eval-speedup-patched build of
        Determinate Nix 3.23.3 (packages/nix-det-pgo), which evaluates this
        flake ~18 % faster than the stock Determinate build while keeping
        lazy-trees.

        Off by default, and the trade-off is not free:

        - `nix.package` feeds both the `nix` client on PATH and the
          `nix-daemon` unit, so the rebuild+switch that activates this flag
          restarts the daemon; in-flight builds are killed, not drained.
        - `nix.package` is also the Nix that `nixos-rebuild` itself runs. If the
          swapped binary is broken, the next switch cannot build or activate
          anything — recovery means fixing the flag from a TTY (edit the file,
          or `nixos-rebuild switch --rollback` with the system's own Nix).
        - the build costs ~12 min per Determinate version the first time it is
          substituted-from-nowhere (PGO: two instrumented builds, two training
          runs, one profile-use build), and it is a local package, so no cache
          serves it: every `nix-src` bump rebuilds it.
        - it must be re-proven on a bump — the five patches are cut against
          upstream 2.35 and Determinate's own commits sit on top.

        Rollback is one line: set this back to false and switch; the definition
        in modules/nix/settings.nix (Determinate's own build) takes over again.
      '';
    };
  };
}
