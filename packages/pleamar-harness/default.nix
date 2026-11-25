##
# Package: pleamar-harness
# Purpose: the three pleamar developer harnesses as one Rust crate:
#   `pleamar-measure` (`files/pleamar/scripts/measure.sh`),
#   `pleamar-describe-snap` (`describe-snap.sh`) and `pleamar-smoke`
#   (`smoke.sh`). The external commands they drive (pleamar, pleamar-wm,
#   ps, systemctl, systemd-run, grim, sway/cage, timeout, setsid, kill, date,
#   mktemp, getconf, id, sleep, column, jq, diff) stay subprocesses with the
#   same argv; scene discovery, tables, snapshots, diffs, proc/cgroup reads and
#   the render matrix are in-process.
#
# The scripts found `files/pleamar` from their own path. A binary in the Nix
# store cannot, so the port reads PLEAMAR_ROOT or walks up from the current
# directory to the flake — documented in the crate README.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "pleamar-harness";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "pleamar developer harnesses: measure, describe-snap and smoke";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.gpl3Plus;
    mainProgram = "pleamar-measure";
  };
}
