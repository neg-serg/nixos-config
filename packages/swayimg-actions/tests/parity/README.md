# Parity harness (migration only)

`run.sh` runs the old zsh helper and the Rust binary in identical sandboxes and compares what a
caller can observe. It exists to prove the port while the shell script is still in the tree; it is
**not** a cargo test and the integration step that deletes
`packages/local-bin/bin/swayimg-actions.sh` also makes it inapplicable.

```sh
# cargo build first, then:
tests/parity/run.sh /tmp/swayimg-target/debug/swayimg-actions
# optional: a different shell script path as the second argument
ONLY=mv-explicit,range-trash-anchor VERBOSE=1 \
  tests/parity/run.sh target/debug/swayimg-actions
```

Requirements on the host: `zsh`, `socat`, `python3` and the usual coreutils. Everything runs under a
fresh `mktemp -d` root: HOME, XDG_DATA_HOME, XDG_PICTURES_DIR, XDG_RUNTIME_DIR and TMPDIR all point
inside it, fake tools shadow every external command, and the only socket is a `UnixListener` created
by `listener.py`. The real `~/tmp`, `~/trash`, `~/.local/share`, wallpaper list and swayimg socket
are never touched.

## What is compared

For each scenario (all actions plus fallbacks: no mark, stale mark, empty mark, cancelled picker,
unknown action, help, missing tools, IPC discovery):

- stdout, stderr and exit code;
- every fake tool's argv (`tools.log`);
- IPC payload bytes, including multiple connections;
- the full sandbox snapshot: tree types, symlink targets and file hashes, which covers moved/copied
  files, `last`, `range_mark` and `wallpaper.list`.

Normalization is intentionally limited to shell bookkeeping that has no Rust equivalent:

- `<script>:<line>: command not found:` → `command not found:` (the port prints
  `<argv0>: command not found: <tool>`);
- zsh's `copy_name:...: write error: broken pipe` / `write error: ...` lines, which appear only when
  a downstream pipeline tool is missing;
- the PID inside `swayimg.<pid>` / `wall_swww.<pid>` temp names.

## Environment notes

- `/etc/zsh/zshenv` (NixOS) sources `set-environment`, which rewrites PATH and the XDG/locale
  variables for the zsh run; the harness sets `__NIXOS_SET_ENVIRONMENT_DONE=1` so both runs see the
  sandbox environment.
- The host's `ug` wrapper is currently broken (ugrep ≥ 7.8 rejects the root-owned
  `--config=/etc/ugrep.conf` for non-root users), which makes the shell's `_list_images` return
  nothing. The harness shadows `ug` with a `grep`-backed fake so the comparison targets the script's
  listing logic; the Rust port does the listing natively and is not affected by that host bug.
- Wallpaper-list scenarios create `$XDG_DATA_HOME/wl`, the directory the append target lives in.
  Without it the shell's redirection fails and zsh prints its own
  `wall:<line>: no such file or directory:` diagnostic before the script's `|| true`; the port
  silently skips the append (the intent of the suppressed redirection), and the resulting filesystem
  is the same (no list). The only difference is that shell diagnostic.
