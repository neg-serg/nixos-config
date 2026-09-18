# Script Catalog

## Hardware — `hwctl` (Rust CLI)

All hardware control scripts have been consolidated into a single Rust CLI:

- `hwctl cpu boost [status|on|off|toggle]` — toggle CPU boost
- `hwctl cpu masks` — suggest kernel masks for V-Cache CPUs
- `hwctl fan setup [--min-temp N] ...` — generate `/etc/fancontrol`
- `hwctl fan reapply [--gpu]` — reapply fan curves after resume
- `hwctl fan auto` — restore automatic fan control
- `hwctl fan manual [PWM]` — set fixed fan speed
- `hwctl fan test-stop [--list] ...` — check if fans can safely stop

See [../packages/hwctl/src/main.rs](../packages/hwctl/src/main.rs) for the full interface.

## Development (`scripts/dev/`)

Run by `just lint`:

- [check-markdown-language.sh](../scripts/dev/check-markdown-language.sh) — docs are English-only
  (no CJK, no Cyrillic); the allowlist covers the two hotkey references that quote Cyrillic keys.
- [check-package-annotations.sh](../scripts/dev/check-package-annotations.sh) — every `pkgs.*` entry
  in a package list carries a trailing `# what it is` comment.
- [check-qml-syntax.sh](../scripts/dev/check-qml-syntax.sh) — parses every QML file with
  `qmlformat --dry-run` (no module deps needed).
- [check-hyprland-vars.sh](../scripts/dev/check-hyprland-vars.sh) — every `$variable` used in the
  Hyprland config is defined somewhere (typos fail silently otherwise).
- [check-all-syntax.sh](../scripts/dev/check-all-syntax.sh) — Lua, JavaScript, JSON/JSONC, YAML,
  TOML and CSS syntax pass over the tree.
- [check-osh-syntax.sh](../scripts/dev/check-osh-syntax.sh) — `osh -n` over every tracked shell
  script (Oils' bash-compatible parser).
- [check-rustfmt.sh](../scripts/dev/check-rustfmt.sh) — rustfmt with the edition from each file's
  nearest `Cargo.toml` (`--fix` formats in place).
- [check-lusty-smoke.sh](../scripts/dev/check-lusty-smoke.sh) — headless smoke test for the
  LustyExplorer nvim picker (`files/nvim/lua/lusty`).
- [check-fuzzy-parity.sh](../scripts/dev/check-fuzzy-parity.sh) — replays the golden vectors
  (`files/quickshell/Helpers/tests/fuzzy-vectors.json`) against the JS port of the lusty-fuzzy
  matcher and re-derives the fixture from the deployed `lusty` when it supports it
  (`--fuzzy-vectors`). See [howto/quickshell-tray-fuzzy.md](./howto/quickshell-tray-fuzzy.md).
- [gen-fuzzy-vectors.sh](../scripts/dev/gen-fuzzy-vectors.sh) — rewrites that fixture from a
  lusty binary; run it when the crate's scoring or ranking changes.

Run by `nix flake check`:

- [check-dsh-worktree.sh](../scripts/dev/check-dsh-worktree.sh) — regression gate for
  `packages/local-bin/bin/dsh-worktree` (flake check `dsh-worktree-guard`).
- [check-dsh-statusline.sh](../scripts/dev/check-dsh-statusline.sh) — regression gate for
  `packages/local-bin/bin/dsh-statusline` (flake check `dsh-statusline-guard`).
- [check-nix-maid-app-dirs.sh](../scripts/dev/check-nix-maid-app-dirs.sh) — every directory under
  `modules/user/nix-maid/apps` is either a real module or listed in that directory's filter; a
  plugin directory missing from the list breaks the whole system evaluation (flake check
  `nix-maid-app-dirs-guard`).

## User scripts — `packages/local-bin/`

84 commands installed into `~/.local/bin` as managed home files by
`modules/user/nix-maid/cli/local-bin.nix`:

- `bin/` — `$PATH` commands; every regular file is installed, `autoSkip` lists the exceptions that
  get a hand-written entry (`kitty-scrollback-nvim`).
- `scripts/` — same mechanism, `scriptSkip` holds the two files whose *content* is templated (`ren`,
  `vid-info.py`, both python helpers needing library paths).

The files are templates: the module runs `lib.replaceStrings` over the text before it becomes a home
file. Tokens:

| token                     | value                                                                           |
| ------------------------- | ------------------------------------------------------------------------------- |
| `@GCC_LIB_DIR@`           | `${pkgs.gcc.cc.lib}/lib` — libstdc++/libgomp for the torch wheels               |
| `@ZLIB_LIB_DIR@`          | `${pkgs.zlib}/lib` — libz                                                       |
| `@ZSTD_LIB_DIR@`          | `${pkgs.zstd.out}/lib` — libzstd (torch ≥ 2.13 links it)                        |
| `@LIBPP@`, `@LIBCOLORED@` | python site-packages of `neg.pretty_printer` / `colored` (`ren`, `vid-info.py`) |
| `@LLAMA_SERVER_BIN@`      | `${pkgs.llama-cpp-vulkan}/bin/llama-server` (marker's fallback)                 |
| `@MUSIC_AI_BASE@`         | `/zero/ai/music-ai` — the music-AI venv tree outside the repo                   |
| `@NIX_KSB_PATH@`          | `kitty-scrollback-nvim` python module path                                      |

Never paste a literal `/nix/store/...` path: it goes stale on the next nixpkgs bump and nothing
keeps it in the store (2026-09-15: 20 scripts pointed at an unrooted `gcc-15.2.0-lib`, and `demucs`
could not `import torch`). Regression gates for two of the scripts live in `flake/checks.nix`
(`dsh-worktree-guard`, `dsh-statusline-guard`).

Manual tools (no recipe or check runs them — call them directly):

- [check-dsh-sessions.sh](../scripts/dev/check-dsh-sessions.sh) — session-format regression gate for
  the dsh package patches (drives `check-dsh-sessions.mjs`).
- [nix-flamegraph.sh](../scripts/dev/nix-flamegraph.sh) — flamegraph SVG of a `nix build --dry-run`
  (perf record + inferno, or `flamegraph.pl` as a fallback).
- [test-ollama-chat.sh](../scripts/dev/test-ollama-chat.sh) — smoke-test the local Ollama chat
  models wired into DSH as the `ollama-local` provider source; needs enough free VRAM.
