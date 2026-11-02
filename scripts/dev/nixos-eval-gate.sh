#!/usr/bin/env bash
# Memoize the two `nix eval` answers an agent loop asks for, keyed on a hash of
# the files the evaluation actually reads.
#
# Why: `nix eval --raw .#…toplevel.drvPath` costs ~9-10 s here (2232 instantiated
# derivations, 3.1 GiB peak), while `…config.system.nixos.label` costs ~0.5-1.3 s
# because it evaluates the module tree without instantiating pkgs. Nix's own eval cache
# cannot help either way: /etc/nixos is a *dirty* worktree most of the time, so
# the eval fingerprint changes on every call and nothing is ever a hit. Both
# answers are pure functions of the tree, so they are memoized on content hashes.
#
# Tier A (default, `just eval-gate`): config.system.nixos.label, the "does the
#   configuration still evaluate" answer for fast feedback after an edit.
#   Key = SHA-256 over the EVALUATION INPUT SET only:
#     - format tag, tier, attr, `nix --version`, resolved repo root;
#     - `git rev-parse HEAD`;
#     - the input path list: `*.nix` (tracked, staged and untracked), `flake.lock`
#       and every non-Nix file a `.nix` file names literally, discovered per run
#       from `readFile|fileContents|fromJSON|pathExists|readDir|neg.path|…` call
#       sites (`files/hardware/udev/*.rules`, `files/gui/zellij/config.kdl`,
#       `secrets/*.sops.yaml`, …);
#     - `git status --porcelain=v1 -z` and `git diff HEAD --binary` restricted to
#       that path list — the content of every changed input, binary included;
#     - the content hash of untracked input files, plus the executable bit (it is
#       part of the store path Nix copies);
#     - the name listing (tracked + untracked) of every directory the `.nix`
#       corpus hands to `readDir`/`tree`/`find`/`pathExists`.
#   So editing a doc, a QML/`.plm` scene or a picture is a HIT (that content is
#   never read during evaluation), while editing any `.nix` file, `flake.lock` or
#   read-in data file is a miss.
#
# Tier B (`--drv`, before a rollout): …toplevel.drvPath. Its key is the WHOLE tree
#   (HEAD + the full `git status --porcelain=v1 -z` + the whole `git diff HEAD
#   --binary` + every untracked file's content hash), not the input set, because
#   the toplevel embeds the flake source tree itself: modules/system/preserve-flake.nix
#   pins `inputs.self.outPath` into an activation script, so *any* tree content —
#   a README, a picture — is an input of the derivation (measured: appending one
#   line to README.md moves the drvPath, and the same edit leaves the tier-A label
#   untouched). Keying tier B on the input set would serve a stale drvPath, i.e. a
#   wrong-direction hit; over-invalidating is the only honest option here.
#
# Honesty rules (both tiers):
#   - a hit is the stored output of a live eval of exactly that state, so it is
#     equal to a live eval by construction; the self-test proves it per run;
#   - anything that cannot be hashed falls through to a real eval with a note on
#     stderr instead of caching: git fails, an input is unreadable or is neither a
#     regular file nor a symlink nor a directory, an untracked directory cannot be
#     listed, or no cache directory is writable;
#   - ignored files are out of both keys on purpose: the flake source copy drops
#     them, so they cannot reach evaluation.
# Known blind spot of the tier-A key: a non-Nix *content* read whose path is
# computed at eval time (a name produced by `readDir` rather than written in the
# source). Changing which files are read always moves the key, since the deciding
# `.nix` file is hashed; only the content of such an already-enumerated file could
# go unnoticed. Nothing in this tree does that today (every `readFile` target is a
# literal path, see `collect_inputs`), and the whole-tree tier-B key covers the
# case when it matters for a rollout.
#
# Usage: nixos-eval-gate.sh [--drv] [--no-cache] [--verbose] [attr]
#   --drv       tier B: evaluate the toplevel drvPath instead of the label
#   --label     tier A explicitly (the default; here so a wrapper can be explicit)
#   --no-cache  skip the cache: always run `nix eval`, store nothing
#   --verbose   print tier, key, cache entry and hit/miss/stored on stderr
#   attr        override the attribute evaluated by the selected tier
#
# Env: XDG_CACHE_HOME selects the cache root (~/.cache); EVAL_GATE_CACHE_DIR
# overrides it wholesale (the self-test uses that to stay hermetic). When neither
# is writable the repo-local `.agent/tmp-nix-cache` scratch dir is used, the same
# fallback `just update` has; with nothing writable the gate just does not cache.
#
# Exit status: `nix eval`'s on a miss, 0 on a hit, 2 on a usage error.
#
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TIER_A_ATTR='nixosConfigurations.trantor.config.system.nixos.label'
TIER_B_ATTR='nixosConfigurations.trantor.config.system.build.toplevel.drvPath'
# Call sites whose string arguments can pull a file or a directory into evaluation.
INPUT_CALL_RE='readFile|fileContents|fromJSON|fromTOML|readDir|pathExists|neg\.path|neg\.rooted|readFileType'

usage() {
  # Print the header's usage block: from `# Usage:` to the end of the comment block.
  awk '/^# Usage:/ { p = 1 } p && !/^#/ { exit } p { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

tier=a # default: the fast feedback tier; `--drv` selects tier B
no_cache=0
verbose=0
attr=""
while [ $# -gt 0 ]; do
  case "$1" in
    --drv) tier=b ;;
    --label) tier=a ;;
    --no-cache) no_cache=1 ;;
    --verbose | -v) verbose=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "nixos-eval-gate: unknown flag: $1" >&2
      usage >&2
      exit 2
      ;;
    *) attr="$1" ;;
  esac
  shift
done
if [ -z "$attr" ]; then
  if [ "$tier" = b ]; then attr="$TIER_B_ATTR"; else attr="$TIER_A_ATTR"; fi
fi

note() { printf 'nixos-eval-gate: %s\n' "$*" >&2; }
debug() {
  if [ "$verbose" -eq 1 ]; then
    note "$*"
  fi
}

REPO_ROOT="$(repo_root)"
ROOT_REAL="$(cd "$REPO_ROOT" && pwd -P)"

# The cache root: EVAL_GATE_CACHE_DIR (self-test) wins, then the documented XDG
# location, then the repo-local scratch cache for sandboxes where $HOME is not
# writable. Nothing writable at all means no caching, not a failure.
resolve_cache_dir() {
  local explicit="${EVAL_GATE_CACHE_DIR:-}"
  local primary="${XDG_CACHE_HOME:-$HOME/.cache}/nixos-eval-gate"
  local fallback="$ROOT_REAL/.agent/tmp-nix-cache/nixos-eval-gate"
  local candidate

  for candidate in ${explicit:+"$explicit"} "$primary" "$fallback"; do
    if mkdir -p "$candidate" 2> /dev/null && [ -w "$candidate" ]; then
      # The repo-local fallback is by design in a sandbox: say it only when asked,
      # so the fast path stays quiet enough for an agent loop.
      if [ "$candidate" != "$primary" ] && [ -z "$explicit" ]; then
        debug "using repo-local cache at $candidate"
      fi
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  [ -z "$explicit" ] || note "cannot write $explicit"
  note "no writable cache directory; not caching"
  return 1
}

# ── tier A: the evaluation input set ────────────────────────────────────────
in_paths=()
in_dirs=()

# Join $1 and $2 into a normalized repo-relative path and leave it in $NORM:
# fold `.`, `..` and repeated slashes. Pure bash with no command substitution —
# the literal scan below runs thousands of times and a fork each would cost more
# than the eval tier A is meant to save. A path escaping the repo leaves "".
NORM=""
normpath() {
  local -a out=()
  local IFS=/ part n
  NORM=""
  for part in $1/$2; do
    case "$part" in
      '' | '.') continue ;;
      '..')
        n=${#out[@]}
        if [ "$n" -eq 0 ]; then
          return 0
        fi
        unset "out[$((n - 1))]"
        ;;
      *) out+=("$part") ;;
    esac
  done
  NORM="${out[*]}"
}

# Record one candidate path: a file/symlink whose content matters, a directory
# whose listing matters, or nothing (outside the tree, or not present at all).
add_input() {
  if [ -z "$1" ]; then
    return 0
  fi
  case "$1" in
    /*) return 0 ;; # absolute: a store path or an out-of-tree file, not an input
  esac
  if [ -n "${input_seen[$1]:-}" ]; then
    return 0
  fi
  if [ -L "$ROOT_REAL/$1" ] || [ -f "$ROOT_REAL/$1" ]; then
    input_seen[$1]=1
    in_paths+=("$1")
  elif [ -d "$ROOT_REAL/$1" ]; then
    input_seen[$1]=1
    in_dirs+=("$1")
  fi
  return 0
}

# Fill in_paths/in_dirs from the `.nix` corpus. Non-zero when the set cannot be
# trusted, and the caller then refuses to cache instead of guessing.
collect_inputs() {
  local file tok base

  declare -gA input_seen=()

  # Every double-quoted literal on a call line, as `file<TAB>literal`: one
  # `git grep` and one awk pass, so the per-literal work below stays fork-free.
  while IFS=$'\t' read -r file tok; do
    case "$tok" in
      '' | *'$'* | *' '*) continue ;; # computed or prose, not a literal path
    esac
    case "$tok" in
      */* | *.*) : ;;
      *) continue ;;
    esac
    add_input "$tok"
    base="${file%/*}"
    if [ "$base" != "$file" ]; then
      normpath "$base" "$tok"
      add_input "$NORM"
    fi
  done < <(
    git -C "$REPO_ROOT" grep -n -E "$INPUT_CALL_RE" -- '*.nix' \
      | awk '
          {
            line = $0
            file = ""
            if (match(line, /^[^:]*:[0-9]+:/)) {
              file = substr(line, 1, index(line, ":") - 1)
              line = substr(line, RLENGTH + 1)
            }
            while (match(line, /"[^"]*"/)) {
              lit = substr(line, RSTART + 1, RLENGTH - 2)
              if (length(lit) >= 2 && length(lit) <= 200) printf "%s\t%s\n", file, lit
              line = substr(line, RSTART + RLENGTH)
            }
          }'
  ) || return 1

  # Every discovered input must be hashable; anything else is a refusal, not a
  # silently smaller input set.
  for file in ${in_paths[@]+"${in_paths[@]}"}; do
    if [ -f "$ROOT_REAL/$file" ] && [ ! -r "$ROOT_REAL/$file" ]; then
      note "cannot hash evaluation input ($file is not readable)"
      return 1
    fi
  done
  return 0
}

# Emit the tier-A key material: the content of the input set, and nothing else.
key_material_a() {
  local -a spec=(':(glob)*.nix' ':(glob)**/*.nix' 'flake.lock')
  local path sum

  collect_inputs || return 1
  spec+=(${in_paths[@]+"${in_paths[@]}"})
  debug "input set: ${#in_paths[@]} file(s), ${#in_dirs[@]} directory reference(s)"

  printf 'format\0v2\0'
  printf 'tier\0a\0'
  printf 'attr\0%s\0' "$attr"
  printf 'nix\0%s\0' "$(nix --version)"
  printf 'root\0%s\0' "$ROOT_REAL"

  printf 'head\0'
  git -C "$REPO_ROOT" rev-parse HEAD || return 1
  printf '\0'

  # The path list itself: adding, removing or renaming an input moves the key.
  printf 'paths\0'
  git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard -z -- "${spec[@]}" \
    | sort -z || return 1
  printf '\0'

  # Directory references are read by name (`readDir`), so their listing is an
  # input even where the files inside only matter at build time.
  printf 'dirs\0'
  printf '%s\0' ${in_dirs[@]+"${in_dirs[@]}"}
  if [ "${#in_dirs[@]}" -gt 0 ]; then
    git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard -z -- "${in_dirs[@]}" \
      | sort -z || return 1
  fi
  printf '\0'

  printf 'status\0'
  git -C "$REPO_ROOT" status --porcelain=v1 -z -- "${spec[@]}" | sort -z || return 1
  printf '\0'

  # Content of every changed input, binary blobs included: without --binary two
  # different images both read "Binary files differ" and would collide the key.
  printf 'diff\0'
  git -C "$REPO_ROOT" diff HEAD --binary --no-color --no-ext-diff --no-textconv \
    --src-prefix=a/ --dst-prefix=b/ -- "${spec[@]}" || return 1
  printf '\0'

  # Untracked inputs are in no diff, so hash their content directly.
  printf 'untracked\0'
  while IFS= read -r -d '' path; do
    if [ -L "$ROOT_REAL/$path" ]; then
      sum="link:$(readlink -- "$ROOT_REAL/$path")" || sum=""
    elif [ -f "$ROOT_REAL/$path" ]; then
      if [ -x "$ROOT_REAL/$path" ]; then
        sum="x:$(sha256sum -- "$ROOT_REAL/$path")" || sum=""
      else
        sum="-:$(sha256sum -- "$ROOT_REAL/$path")" || sum=""
      fi
    else
      note "cannot hash evaluation input ($path is not a regular file or symlink)"
      return 1
    fi
    if [ -z "$sum" ]; then
      note "cannot hash evaluation input ($path is not readable)"
      return 1
    fi
    printf '%s\0%s\0' "$path" "$sum"
  done < <(git -C "$REPO_ROOT" ls-files --others --exclude-standard -z -- "${spec[@]}") || return 1
  printf '\0'

  printf 'end\0'
  return 0
}

# ── tier B: the whole tree ──────────────────────────────────────────────────
# The toplevel embeds the flake source tree (preserve-flake pins self.outPath), so
# every tracked file's content is an input of the derivation: key on all of it.
key_material_b() {
  local path sum

  printf 'format\0v2\0'
  printf 'tier\0b\0'
  printf 'attr\0%s\0' "$attr"
  printf 'nix\0%s\0' "$(nix --version)"
  printf 'root\0%s\0' "$ROOT_REAL"

  printf 'head\0'
  git -C "$REPO_ROOT" rev-parse HEAD || return 1
  printf '\0'

  printf 'status\0'
  git -C "$REPO_ROOT" status --porcelain=v1 -z | sort -z || return 1
  printf '\0'

  printf 'diff\0'
  git -C "$REPO_ROOT" diff HEAD --binary --no-color --no-ext-diff --no-textconv \
    --src-prefix=a/ --dst-prefix=b/ || return 1
  printf '\0'

  printf 'untracked\0'
  while IFS= read -r -d '' path; do
    if [ -L "$ROOT_REAL/$path" ]; then
      sum="link:$(readlink -- "$ROOT_REAL/$path")" || sum=""
    elif [ -f "$ROOT_REAL/$path" ]; then
      if [ -x "$ROOT_REAL/$path" ]; then
        sum="x:$(sha256sum -- "$ROOT_REAL/$path")" || sum=""
      else
        sum="-:$(sha256sum -- "$ROOT_REAL/$path")" || sum=""
      fi
    else
      note "cannot hash untracked entry ($path is not a regular file or symlink)"
      return 1
    fi
    if [ -z "$sum" ]; then
      note "cannot hash untracked entry ($path is not readable)"
      return 1
    fi
    printf '%s\0%s\0' "$path" "$sum"
  done < <(git -C "$REPO_ROOT" ls-files --others --exclude-standard -z) || return 1
  printf '\0'

  printf 'end\0'
  return 0
}

tree_key() {
  local material key
  material="$(mktemp "${TMPDIR:-/tmp}/nixos-eval-gate.XXXXXXXX")" || return 1
  if [ "$tier" = b ]; then
    key_material_b > "$material" || {
      rm -f "$material"
      return 1
    }
  else
    key_material_a > "$material" || {
      rm -f "$material"
      return 1
    }
  fi
  key="$(sha256sum < "$material")" || {
    rm -f "$material"
    return 1
  }
  rm -f "$material"
  printf '%s\n' "${key%% *}"
}

live_eval() {
  (
    cd "$ROOT_REAL" && nix eval --raw ".#$attr"
  )
}

cache_dir=""
if [ "$no_cache" -eq 0 ]; then
  cache_dir="$(resolve_cache_dir)" || cache_dir=""
fi

key=""
if [ -n "$cache_dir" ]; then
  if key="$(tree_key)"; then
    debug "tier=$tier attr=$attr key=$key"
    entry="$cache_dir/$key"
    if [ -f "$entry" ]; then
      value=""
      value="$(< "$entry")"
      # $(< file) strips the trailing newline; an embedded one means a corrupt
      # write (the write is atomic, so this should not happen).
      case "$value" in
        '' | *$'\n'*) note "ignoring malformed cache entry $entry" ;;
        *)
          debug "hit $entry"
          printf '%s\n' "$value"
          exit 0
          ;;
      esac
    fi
    debug "miss $entry"
  else
    note "the input set cannot be hashed; running a live eval and caching nothing"
    key=""
  fi
else
  debug "cache disabled"
fi

if ! value="$(live_eval)"; then
  note "nix eval failed"
  exit 1
fi

# Atomic write: a temp file in the same directory, renamed over the entry, so a
# concurrent reader sees either the whole value or no entry at all.
if [ -n "$key" ] && [ -n "$cache_dir" ] && [ -n "$value" ]; then
  tmp="$cache_dir/.$key.$$"
  if printf '%s\n' "$value" > "$tmp" 2> /dev/null && mv -f "$tmp" "$cache_dir/$key" 2> /dev/null; then
    debug "stored $cache_dir/$key"
  else
    rm -f "$tmp" 2> /dev/null || true
    note "could not write the cache entry in $cache_dir"
  fi
fi

printf '%s\n' "$value"
