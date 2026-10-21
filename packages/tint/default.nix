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
#    `--theme light|vivid|mono|none`, `NO_COLOR` and `TERM=dumb` are one
#    table swap instead of a second code path.
#
# Spans never nest: all candidates are sorted by (start, priority, length) and
# overlapping ones are dropped (`src/hit.rs`), so the renderer walks a line once.
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
# 32 MB / 261 303 lines of `journalctl -b --no-pager` through
# `tint -r journalctl --color=always`: 224 ms, 1 125 427 spans, 137 MiB/s on the
# 9950X3D (2026-10-21). The 48 unit tests run in the build (`cargo test`).

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
