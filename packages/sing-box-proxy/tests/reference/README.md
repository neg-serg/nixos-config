# Golden-fixture oracle

The golden files under `tests/fixtures/golden/` were produced by the original Python programs that
used to live inside `packages/local-bin/bin/proxy` (bash heredocs). They are the committed reference
for byte-level parity tests of the Rust port.

- `extract_oracle.py` mechanically extracts the three heredocs (`gen_cfg`, the bootstrap patcher and
  `validate_nodes`) from the legacy shell script into a given output directory. The extracted bodies
  are intentionally not committed: they are unformatted Python (`import a, b`, a missing `os`
  import, one-line `if` bodies) and would fail this repository's `ruff`/`black` gates.
- `regenerate.sh` extracts the oracle into a throwaway directory (default legacy path
  `/etc/nixos/packages/local-bin/bin/proxy`, override with `PROXY_LEGACY`) and rewrites the golden
  JSON/stderr files from the committed synthetic fixtures. It needs `python3` and no network, and
  only works while the legacy shell script still exists — the goldens are already committed, so it
  is a one-time provenance tool, not part of the test cycle.
- `gen_cfg` — config generator (`build_config` in Rust).
- `bootstrap_patch` — heals an existing config (DNS/route, `tg-auto`, urltest interval, LAN inbound
  auth). Its stderr golden keeps only the deterministic `:: Config:` messages: the original writes
  the healed config and then crashes with `NameError: os` because it calls `os.chmod` without
  importing `os`. The Rust port performs the chmod and exits 0 (documented intentional deviation).
- `validate_nodes` — TCP scan + e2e probe used by `refresh`. It produced no goldens (it needs the
  network and sing-box); the port's semantics are pinned by `tests/validation.rs` instead.

`cargo test` never runs Python: golden tests compare the Rust output against the committed files
only.
