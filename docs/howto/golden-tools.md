# Golden CLI tool set (golden tool set)

The list of fast modern replacements for the standard utilities that agents (dsh, Codex, etc.) must
use — and preferably the human in an interactive shell on this machine. It is the single source of
truth: the agent rules are duplicated in `/etc/nixos/AGENTS.md` (section "Golden tool set"), and the
short version for dsh lives in the skill `~/.dsh/skills/golden-tools/SKILL.md`.

## Why

The replacements are faster and lighter than the classic utilities for several reasons:

- **Parallelism and SIMD**: ripgrep/fd/fdupes-like tools walk the tree on multiple threads and use
  SIMD scanning (memchr), whereas `grep -r`/`find` are single-threaded.
- **Respect for `.gitignore`**: `rg`/`fd` skip `.git/`, `node_modules/`, and everything listed in
  ignore files by default — no need to write `--exclude-dir` manually.
- **Less memory, less waste**: `rg` does not load whole files into memory, `fd` does not materialize
  the tree in memory, and `bat` reads only the visible range of lines.
- **Better output**: colors, syntax highlighting, human-readable sizes, git status in listings.
- **Fewer tokens for the agent**: a single `rg 'pattern' dir` call with `--no-heading` gives compact
  output instead of multi-line `grep -rn --color=never`.

## Replacement table

| Legacy (slow/clunky)            | Golden (fast/convenient) | Status on this host           | Where it is wired in the repo                                         |
| ------------------------------- | ------------------------ | ----------------------------- | --------------------------------------------------------------------- |
| `grep -r`                       | `rg` (ripgrep)           | ✅ installed                  | `modules/cli/tools.nix`, `modules/user/nix-maid/cli/search.nix`       |
| `grep -r` (interactive)         | `ugrep` / `ug`           | ✅ installed                  | `modules/cli/tools.nix` + `modules/cli/ugrep.nix` (`/etc/ugrep.conf`) |
| `find`                          | `fd`                     | ✅ installed                  | `modules/cli/tools.nix`, nix-maid `cli/search.nix`                    |
| `cat`                           | `bat`                    | ✅ installed, alias `cat`     | nix-maid `cli/search.nix`, alias in `lib/aliae.nix`                   |
| `ls`                            | `eza`                    | ✅ installed, alias `ls`      | `modules/cli/tools.nix`, alias in `lib/aliae.nix`                     |
| `diff`                          | `delta`                  | ✅ installed (git-pager)      | `modules/cli/tools.nix`, nix-maid `cli/git.nix`                       |
| `du`                            | `dust` / `ncdu`          | ✅ installed                  | `modules/cli/tools.nix`                                               |
| `df`                            | `duf`                    | ✅ installed                  | `modules/cli/tools.nix` (`pkgs.neg.duf`)                              |
| `top`                           | `btop`                   | ✅ installed                  | `modules/monitoring/pkgs/default.nix`, nix-maid `cli/monitoring.nix`  |
| `ps`                            | `procs`                  | ⏳ being added (`pkgs.procs`) | `modules/cli/tools.nix`                                               |
| `sed 's/a/b/'` (simple replace) | `sd`                     | ⏳ being added (`pkgs.sd`)    | `modules/cli/tools.nix`                                               |
| `sed`/`awk` for JSON            | `jq`                     | ✅ installed                  | `modules/cli/file-ops.nix`, `modules/text/manipulate-packages.nix`    |
| `cd` + remembering paths        | `zoxide` (`z`)           | ✅ installed                  | `modules/cli/tools.nix`                                               |
| interactive selection           | `fzf`                    | ✅ installed                  | nix-maid `cli/search.nix` (+ `FZF_*` variables)                       |
| benchmarking by eye             | `hyperfine`              | ✅ installed                  | `modules/dev/pkgs/default.nix`                                        |
| `tree`                          | `erdtree` / `eza --tree` | ✅ installed                  | `modules/cli/tools.nix`                                               |

Legend: ✅ — already on the system; ⏳ — being added in `modules/cli/tools.nix`.

## Configuration (already set up)

- **rg**: `~/.config/ripgrep/ripgreprc` — `--no-heading --smart-case --follow --hidden` + exclusions
  of `.git/`, `node_modules/`, etc. (nix-maid `cli/search.nix`). For agents, `--no-heading` gives
  compact `path:line:match` lines. Threads: `--threads=32` (by default ripgrep uses only 12 workers;
  on odin's 16C/32T all 32 are used).
- **bat**: `~/.config/bat/config` — the `ansi` theme, no paging or frames (handy in pipes).
- **fzf**: `FZF_DEFAULT_COMMAND` is already built on `fd` (`fd --type=f --hidden --exclude=.git`);
  file previews via `bat`, directory previews via `eza --tree`.
- **git**: pager = `delta` (nix-maid `cli/git.nix`), plus `diff-so-fancy` for formatting.
- **ugrep**: system-wide `/etc/ugrep.conf` (colors, `hidden`, `no-pager`, `jobs=32`, etc.) —
  `modules/cli/ugrep.nix`; the `ugrep`/`ug` wrappers load it via `--config` (in ugrep 7.5 the
  `UGREP_CONFIG_FILE` variable does not work) — `modules/cli/tools.nix`. `jobs=32` engages all 32
  threads instead of the default 12 workers.
- **shell aliases**: `ls`→`eza`, `cat`→`bat` (cross-shell via aliae, `lib/aliae.nix`); Nix aliases
  in `environment.shellAliases` (`modules/cli/tools.nix`).

## Examples for agents

Code search (compact, honoring .gitignore):

```bash
rg 'pattern' /path/to/dir            # files + line numbers, recursive by default
rg -l 'pattern' .                    # filenames only
rg -t nix 'mkIf' modules/            # .nix only
rg --pcre2 '(?<=foo)bar' .           # PCRE lookbehind (rg -r is REPLACE, not recursion!)
```

File search:

```bash
fd '\.nix$' modules/                 # instead of find modules/ -name '*.nix'
fd -e md -x wc -l {}                 # run a command for each result
fd -t d 'venv'                       # directories only
```

Reading and processing:

```bash
bat --line-range :50 file.nix        # first 50 lines with highlighting
jq -r '.[].name' flake.lock          # instead of sed/awk on JSON
sd 'old' 'new' file.txt              # simple replacement; sd -s is literal, without regex
procs --tree                         # process tree instead of ps -ef
```

Benchmarking (when you need to prove the replacement is faster):

```bash
hyperfine 'grep -r foo .' 'rg foo .' # compare legacy vs golden
```

## When NOT to use the replacements

- **Scripts that must work beyond this machine**: on remote/non-NixOS hosts `rg`/`fd` may not be
  installed — write portably (POSIX `grep`/`find`) or explicitly check for their presence.
- **POSIX contexts**: `rg` has `grep -o`/`-c`/`-B/-A`, but the semantic differences are subtle (for
  example `rg -r` = replace) — check the flags when porting.
- **PCRE specifics**: rg uses Rust regex by default (no lookbehind); you need `--pcre2`.
- **Binary files / archives**: classic `grep -a`/`zgrep` is sometimes more convenient; `ugrep`
  exists for this (it handles archives/binaries). Rare exotic `grep` flags (for example `-P` in old
  versions) have no equivalent — then stay on `grep`.
- **Interactive pagers and TTYs**: `bat` in a pipe without `--paging=never`/`-p` may behave like a
  pager; for agents always add `-p` or `--paging=never`.

## How the golden set is arranged in this repo

| Layer                   | What it contains                                             | Where                                                                                                       |
| ----------------------- | ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| Rules for agents (I/we) | hard rules for choosing tools, loaded into every session     | `AGENTS.md` (section "Golden tool set")                                                                     |
| Reference               | this page                                                    | `docs/howto/golden-tools.md`                                                                                |
| Skill for dsh           | short version of the rules, visible in the dsh skill catalog | `~/.dsh/skills/golden-tools/SKILL.md`                                                                       |
| Packages and configs    | tool installation, aliases, rg/bat/fzf/git/ugrep configs     | `modules/cli/tools.nix`, `modules/cli/ugrep.nix`, nix-maid `cli/search.nix`, `cli/git.nix`, `lib/aliae.nix` |

Verify the installation:
`command -v rg fd bat eza delta jq zoxide duf dust ncdu btop procs sd hyperfine`.

Package changes require a system rebuild (`nh os switch /etc/nixos#odin --option substitute false`);
changes under `~/.dsh/skills/` are picked up by a new dsh session without a rebuild.
