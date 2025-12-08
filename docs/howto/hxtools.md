# hxtools: quick usage guide

`pkgs.neg.hxtools` is pulled in by the monitoring role or the optional dev `pkgs.misc` bundle. For
ad-hoc use from this repo: `nix shell .#hxtools -c <command>` (or `nix shell nixpkgs#hxtools`
outside the flake).

## Git and stats

| Command | Purpose | Example |
| --- | --- | --- |
| `git forest [--all --style=10 --sha]` | Console commit tree with branch lines. | `git forest --all --style=10 --sha | less -RS` |
| `git-blame-stats [rev] [paths...]` | Per-author line counts via `git blame`; handy to find ownership. | `git-blame-stats HEAD src/` |
| `git-author-stat [range]` | Top authors by commit count in a range. | `git-author-stat v1.0..v1.1` |
| `git-revert-stats [range]` | Who reverts most often in a range. | `git-revert-stats origin/main~200..` |
| `git-track remote/branch` | Configure tracking for the current branch. | `git-track origin/main` |

`git forest` also accepts `--svdepth=N` for denser sub-vines and `--sha` to print abbreviated SHAs for
copy/paste.

## Monitoring and admin

| Command | Purpose | Example |
| --- | --- | --- |
| `hxnetload <iface> [interval]` | Live Rx/Tx in KB/s from `/proc/net/dev`; interval can be seconds or, if >50000, microseconds. | `hxnetload wlan0 1` |
| `sysinfo [-v]` | Single-line summary (OS, kernel, CPU, RAM, disks); good for chat/tickets. | `sysinfo` |
| `tailhex [-f] [-B bytes] <file>` | Hex dump with `tail -f`-style follow mode; useful for binary logs. | `tailhex -f /var/log/wtmp` |
| `wktimer -A/-S/-L <name>` | Simple work timers: create, stop, and list (`~/.timers`). | `wktimer -A task && wktimer -S task && wktimer -L` |

## Text, archives, media

| Command | Purpose | Example |
| --- | --- | --- |
| `pegrep <perl-regex> files...` | Perl-regex grep with multiline support. | `pegrep '}\s*else' $(find src -name '*.cpp')` |
| `pesubst -s <src> -d <dst> [-m mods] files...` | Perl-regex substitution across whole files (sed-style). | `pesubst -s foo -d bar -ms config.yaml` |
| `qtar [-x] [--ext|--svn] <archive> <paths...>` | Create tar archives with sorted input; `-x` drops .git/.svn/etc. | `qtar -x --ext backup.tar.gz src docs` |
| `qplay [-i part] [-q part] [-r rate] [files...] | aplay -f dat -c 1` | Convert QBASIC PLAY strings to PCM and stream into `aplay`; mixes square+sine by default. | `echo "L16O2CDEFGAB>L4C" | qplay - | aplay -f dat -c 1` |

See `man hxtools` for the full roster of utilities, including rarer ones like `peicon`, `mailsplit`,
and the game-archive extractors.
