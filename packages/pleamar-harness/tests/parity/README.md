# Parity originals

These are byte-for-byte copies of the three shell harnesses the crate ports:

- `measure.sh` from `files/pleamar/scripts/measure.sh` —
  `2e17064a10399a5ab02d2385a12902ba9f2af9bfd57263f3cb244dd9528e4ad5`
- `describe-snap.sh` from `files/pleamar/scripts/describe-snap.sh` —
  `780957901758e605cbd01fcaf8065944932cebb0c1b5683227a55cb906ad9acf`
- `smoke.sh` from `files/pleamar/scripts/smoke.sh` —
  `28607709e974a0ab15ca65301ddf6c5ff12f89f0e3bb7e812c98dbd09dc4c37b`

They are test fixtures, not a second copy to maintain: `tests/parity.rs` copies one into a temporary
fixture repo's `scripts/` directory (the scripts resolve `PROJECT_DIR` from their own path) and runs
it with the same fake tools as the port.
`git diff --no-index files/pleamar/scripts/measure.sh packages/pleamar-harness/tests/parity/original/measure.sh`
must stay empty.

The copies exist because a Nix build sandbox only sees the crate's own source; the parity harness
must keep working there. Do not edit them to make a parity test pass — fix the port or record a
deviation in the crate README.
