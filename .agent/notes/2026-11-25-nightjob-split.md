# 2026-11-25 — nightjob moved to its own repository

Status: extracted, published (`github:neg-serg/nightjob`, `130cde5`), wired and built. The suite the
`llm-proxy` note asked for exists now: 19 stdlib tests, run by `nix flake check`, and they found a
real (if small) bug on the first run.

Repository: <https://github.com/neg-serg/nightjob> (public). Live checkout: `~/src/nix/nightjob`.

## What moved out of this tree

| was here                                                                                                              | now                                                             |
| --------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `modules/dev/nightjob.py` (1565 lines)                                                                                | `nightjob.py` at the repository root                            |
| the wrapper in `modules/dev/rocm.nix` (python3 + fzf + rocm-smi + pciutils + systemd + libnotify + coreutils on PATH) | `package.nix`                                                   |
| —                                                                                                                     | `test_nightjob.py`, `flake.nix` with `checks.unit`, `README.md` |

## Decisions taken with the move

- **Tests before extraction, as the `llm-proxy` note asked.** The suite needs no device: it covers
  the duration and size grammars, the state-directory contract (`STATE_DIR` is patched in the test),
  the CLI surface (`build_parser`), the exit-code wording and the shell quoting that builds the
  supervisor's command line.
- **The wrapper moved with the script.** The tool PATH (fzf, `rocm-smi`, lspci, `systemd-run`,
  `notify-send`, coreutils) used to be inlined in the module; it is the repository's now, and the
  caller's PATH still rides behind it, so `hyprctl` and `llmctl` keep coming from the session.
- **The suite found a bug.** `_describe_rc` returned `signal signal 999` for a signal number the
  kernel enum does not name (the fallback already carried the word); it prints the number alone now.
- **The host keeps the flag and the venv.** `features.dev.ai.rocm` still decides whether the tool is
  installed, `modules/dev/rocm.nix` is down to the package list, and the training environment stays
  a pip venv — nothing about torch enters the closure.
- **Pinned to the host's nixpkgs** in the repository's own `flake.lock`, so
  `nix build`/`nix flake check` there reuse the same package set the host builds against.

## How the host consumes it

- `flake.nix`: `nightjob` (`github:neg-serg/nightjob`, `inputs.nixpkgs.follows`).
- `packages/overlay.nix`: `final.callPackage (inputs.nightjob + "/package.nix") { }` →
  `pkgs.neg.nightjob`.
- `modules/dev/rocm.nix`: installs `pkgs.neg.nightjob` next to `rocm-smi`; no script, no wrapper.

## Verification done that day

- In the repository: `python3 -m unittest discover` (19 tests), `nix flake check` (builds the
  package and runs the suite as `checks.unit`), `nix build .#default`.
- Here: `just fmt`, `just lint` (17 gates), `just check`, the toplevel eval and build, the switch,
  and `nightjob --help` from the new store path.

## Gaps to fix later

1. **No `LICENSE` file in the repository.** The package meta carries no `license` field rather than
   inventing one; add the file and the field together.
1. **The device paths are still untested.** `preflight`, `collect_apps`, the supervisor and the
   report need a ROCm card and a live systemd user manager, so the suite covers their inputs and
   formatting, not the run itself.
