# tint — colouriser for command-line programs that print plain text.
#
# ## Why this exists
#
# The classic answers to "make `df` readable" are `grc` (a Perl wrapper with a
# conf file per tool), `cope` (Perl too) and `ccat`. All of them pay a script
# interpreter per invocation and only know the tools someone wrote a conf for.
# `tint` is one Rust binary with no crate dependencies: ~1 ms of startup, so it
# can sit in front of every diagnostic command in the shell without turning a
# 20 ms `df` into a 120 ms one.
#
# ## How colouring is decided
#
# Three layers, cheapest first:
#
# 1. *Scanners* (`src/scan.rs`) classify tokens by their shape — byte size,
#    percentage (with thresholds), duration, temperature, IPv4/IPv6/CIDR, MAC,
#    path, URL, quoted string, timestamp (ISO, syslog, clock), git-style hash,
#    `key=value` key, severity words. A program nobody wrote rules for still
#    gets useful colouring, and each classifier is a hand-written byte scan, not
#    a regex: no per-line allocation, no compiled state machine.
# 2. *Rulesets* (`src/ruleset.rs`) add what is specific to one tool: `ss` state
#    names, `lsblk` type words, `nix build` phases, `kubectl` pod states, plus
#    line prefixes (`;; ANSWER SECTION:`, `--- `, `error:`). A ruleset is a
#    delta on the scanners, so adding a tool is a few lines of table.
# 3. *Themes* (`src/theme.rs`) map the semantic slots to ANSI styles, so
#    `--theme light|neg|vivid|mono|none`, `NO_COLOR` and `TERM=dumb` are one
#    table swap instead of a second code path. `dark` (the default) paints with
#    the terminal's own 16 colours — no assumption about the palette, so it
#    follows whatever theme the terminal runs. `neg` is the `neg.nvim` palette
#    as truecolor, taken from the editor's own palette.lua and
#    groups/diagnostics.lua; the one deviation is the error family, which uses
#    the bright red of the same palette (`#cf4f88`, 5.1:1 on black) instead of
#    the editor's diff-delete burgundy (`#6b0f2a`, 1.7:1), because a one-line
#    CLI error has no undercurl to carry the message.
#
# Spans never nest: all candidates are sorted by (start, priority, length) and
# overlapping ones are dropped (`src/hit.rs`), so the renderer walks a line once.
#
# ## Streaming
#
# The output loop is built for live sources, not just files: a line is forwarded
# as soon as its terminator arrives, and whatever is buffered goes out whenever a
# read comes back short — which is what a slow pipe, `journalctl -f`, `tail -f`,
# `dmesg -w` or `ping` look like. A carriage return counts as a terminator, so
# in-place progress redraws (curl, cargo, rsync, nix) are coloured and flushed
# instead of waiting for a newline that never comes; a `\r\n` pair stays intact
# even when its two bytes arrive in different reads. Latency is pinned by tests:
# a probe reader asserts the first chunk was written before the second was read.
#
# ## Modes
#
#     tint -- df -h          # run the command, colourise stdout and stderr
#     df -h | tint -r df     # colourise a pipeline
#     tint --list            # rulesets, with their extras
#     tint --show df         # what a ruleset matches and how many rules compiled
#     tint --shell zsh       # shell integration (zsh, bash, fish, list)
#
# When colour is off — a pipe, `NO_COLOR`, `TERM=dumb` — the wrapper mode
# `exec`s the command instead of copying it, so a pipeline pays one `exec` and
# keeps the command's own exit code and signal behaviour.
#
# ## Where the shell wrappers come from
#
# `tint --shell zsh` prints one guarded function per command in the builtin
# table: `df`/`duf`, `du`/`dust`, `free`, `lsblk`, `ip`, `ss`/`netstat`, `ping`,
# `traceroute`, `dig`/`host`/`nslookup`, `mount`/`findmnt`, `dmesg`, `ps`,
# `lsof`, `sensors`, `lspci`/`lsusb`, `smartctl`/`nvme`, `uptime`/`w`/`last`,
# `env`, `find`, `tar`, `diff`, `nmap`, `iptables`/`nft`, `systemd-analyze`.
# files/shell/zsh/02-cmds.zsh sources it once per interactive shell, deferred,
# so the list lives here and in the user's config, never in a second copy.
#
# Everything else is *deliberately* not wrapped. A wrapped command sees a pipe
# where a terminal used to be, which would take `git`'s pager (delta),
# `journalctl`/`systemctl`/`man` paging, `cargo`/`nix`/`nh` build progress,
# `docker`/`kubectl -it` and the `python` REPL. Those rulesets exist and are
# reached explicitly — `journalctl -b | tint -r journalctl` — and the opt-in list
# is one commented line in files/tint/config.toml.
#
# ## Already-coloured lines
#
# A line that carries ANSI escapes is passed through untouched by default
# (`--ansi=skip`): the program coloured it itself, and re-colouring fights it.
# `--ansi=extend` colours such lines anyway.
#
# ## Config
#
# `~/.config/tint/config.toml`, a flat TOML subset (deployed from
# files/tint/config.toml):
#
#     theme = "dark"
#     theme.style.hash = "idx:221"
#     wrap = "go rustup"           # extra commands to wrap
#     skip = "find tar"            # never wrap these
#     keyword.FATAL = "red,bold"   # word rule, raw style or theme slot
#     prefix.!!! = "brightred"     # line-start rule
#     suffix.done = "ok"           # line-end rule
#     literal.dbg! = "idx:141"     # anywhere in the line
#
# ## Measured
#
# On the 9950X3D, 2026-10-21:
#
# - throughput: 32 MB / 261 303 lines of `journalctl -b --no-pager` through
#   `tint -r journalctl --color=always` take 311 ms at 1 109 506 spans, i.e.
#   98 MiB/s on the most token-dense input available (log lines carry
#   timestamps, PIDs, addresses, paths, quoted strings and durations). Plain
#   prose is faster; the scanners are the cost, and they are what buys colour
#   for programs nobody wrote rules for.
# - startup: `df -h` 1.1 ms, `tint -- df -h` 1.3 ms, `tint --color=always --
#   df -h` 1.4 ms, so a wrapper adds 0.2-0.3 ms to a short command.
# - streaming: a one-line-at-a-time stream is forwarded per read, pinned by the
#   probe test (the first chunk is written before the second is read).
#
# The 58 unit tests run in the build (`cargo test`).

{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "tint";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Colouriser for command-line program output (scanners + rulesets, no dependencies)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "tint";
  };
}
