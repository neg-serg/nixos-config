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
#
# The checks are hermetic: fake pleamar/pleamar-wm/ps/systemctl/grim/... in a
# temporary bin dir, a temporary HOME/XDG sandbox, no session and no network.
# `tests/parity.rs` also runs unmodified copies of the original shell scripts
# (tests/parity/original/) against the same fakes and compares stdout, stderr,
# exit codes, artifacts and the argv of the contract tools.
{
  lib,
  rustPlatform,
  bash,
  coreutils,
  diffutils,
  findutils,
  gawk,
  gnugrep,
  gnused,
  jq,
  perl,
  procps,
}:

rustPlatform.buildRustPackage {
  pname = "pleamar-harness";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  doCheck = true;

  # The tests and the parity harness use these host tools (the fakes are shell
  # scripts; jq/diff/sort are the real ones the scripts called). No network,
  # session or cgroup is touched.
  nativeCheckInputs = [
    bash
    coreutils
    diffutils
    findutils
    gawk
    gnugrep
    gnused
    jq
    perl
    procps
  ];

  meta = lib.mkMeta {
    description = "pleamar developer harnesses: measure, describe-snap and smoke";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.gpl3Plus;
    mainProgram = "pleamar-measure";
  };
}
