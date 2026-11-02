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
# Tier-B evaluation shape: `--option eval-cores` alone buys nothing for
#   `nix eval --raw …drvPath` — the executor is created and shuts down with zero
#   work items, because only three call sites ever fan out (value-to-json.cc,
#   search.cc, flake-schemas.cc) and print.cc has none. Evaluation does
#   parallelise when the *expression* fans out, through Determinate's
#   undocumented two-argument `builtins.parallel` (`parallel a b` forces `a`
#   concurrently and returns `b`), so tier B now evaluates
#     cs: let c = cs.trantor
#         in builtins.parallel (map (p: p.drvPath)
#                                  c.config.environment.systemPackages)
#                               c.config.system.build.toplevel.drvPath
#   Bare `nix eval`, one warm cache, 4 interleaved runs (median / min): plain
#   shape 8.44 s / 8.35 s, this shape 3.45 s / 3.31 s = 2.4x. End to end the gate
#   goes 9.00 s / 8.74 s -> 3.72 s / 3.67 s (5 interleaved runs of each), and a
#   cache hit still costs 37 ms, the same as before this change. Core count comes
#   from TIER_B_CORES below. The primop exists only in Determinate builds, so it
#   is probed once (`builtins ? parallel`) before the first tier-B evaluation and
#   the gate falls back to the plain shape when it is missing: it must never fail
#   because of a Determinate-only primop, and it must never claim the fast path.
#   Parallelism is a *forcing order*, not an input — it is not part of the cache
#   key, so both shapes share one key space and the self-test asserts the key and
#   the answer are byte-identical either way.
#
# One call, many answers: the tier-B evaluation can return
#   {label, drvPath, toplevel, name, system} from a single run at no extra cost
#   (spike: label alone 0.46 s, drvPath alone 9.09 s, all five together 9.08 s),
#   so `--field NAME` prints one of them and `--json` prints the whole set from
#   one evaluation instead of one evaluation per answer. Tier A stays the cheap
#   label path; every tier-B run forces the system regardless.
#
# Proof record: every cache write also stores `<key>.record` beside the answer —
#   tier, selector, attr, evaluation shape, `nix --version`, HEAD, the answer,
#   the timestamp, `git ls-files -s` for the tree and the exact key material the
#   answer was derived from. A wrong-looking answer can therefore be re-derived
#   by hand without guessing which inputs the cache believed in. `--verbose`
#   prints it. This is the cheapest insurance against the one failure class that
#   matters here: a confident stale answer.
#
# This gate is the final architecture for eval latency, not a stopgap: a
#   spike costed an incremental eval server and rejected it — locality is zero
#   (a one-option module edit still pays the full ~9 s, and the flake source path
#   is not stable even for identical bytes). The honesty rules below are what
#   carries the design, so they are not negotiable for a faster number.
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
# Usage: nixos-eval-gate.sh [--drv] [--no-cache] [--verbose] [--field NAME | --json] [attr]
#   --drv       tier B: evaluate the toplevel drvPath instead of the label
#   --label     tier A explicitly (the default; here so a wrapper can be explicit)
#   --no-cache  skip the cache: always run `nix eval`, store nothing
#   --verbose   print tier, key, cache entry, hit/miss/stored, and the proof
#               record on stderr
#   --field NAME  tier B only: print one of label, drvPath, toplevel, name,
#                 system from the single evaluation that returns the whole set
#   --json      tier B only: print that whole set as JSON
#   attr        override the attribute evaluated by the selected tier
#
# Env: XDG_CACHE_HOME selects the cache root (~/.cache); EVAL_GATE_CACHE_DIR
# overrides it wholesale (the self-test uses that to stay hermetic). When neither
# is writable the repo-local `.agent/tmp-nix-cache` scratch dir is used, the same
# fallback `just update` has; with nothing writable the gate just does not cache.
# NIX overrides the `nix` binary (the self-test wraps it to exercise the missing
# primop); EVAL_GATE_PARALLEL=off forces tier B's plain shape, i.e. the same
# command and key with no `builtins.parallel` fan-out.
#
# Exit status: `nix eval`'s on a miss, 0 on a hit, 2 on a usage error.
#
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TIER_A_ATTR='nixosConfigurations.trantor.config.system.nixos.label'
TIER_B_ATTR='nixosConfigurations.trantor.config.system.build.toplevel.drvPath'
# Call sites whose string arguments can pull a file or a directory into evaluation.
INPUT_CALL_RE='readFile|fileContents|fromJSON|fromTOML|readDir|pathExists|neg\.path|neg\.rooted|readFileType'
# Tier-B fan-out width. Only set when the expression itself fans out through
# `builtins.parallel`; `eval-cores` alone does nothing for `nix eval --raw`.
# Spike measurements on one warm cache (9.7 s single-core): 4 = 4.01 s,
# 8 = 4.03 s, 16 = 3.86 s, `auto` (= 32 here) worse than every explicit number.
TIER_B_CORES=16
# The five answers one tier-B evaluation returns together. `outPath` is
# deliberately not a field name: an attrset carrying `outPath` is printed by Nix
# as that path alone (the derivation shortcut in print.cc), which would silently
# turn `--json` into a single string.
TIER_B_FIELDS='{ label = c.config.system.nixos.label; drvPath = c.config.system.build.toplevel.drvPath; toplevel = c.config.system.build.toplevel.outPath; name = c.config.system.build.toplevel.name; system = c.pkgs.stdenv.hostPlatform.system; }'

usage() {
  # Print the header's usage block: from `# Usage:` to the end of the comment block.
  awk '/^# Usage:/ { p = 1 } p && !/^#/ { exit } p { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

tier=a # default: the fast feedback tier; `--drv` selects tier B
no_cache=0
verbose=0
attr=""
field=""
json_out=0
while [ $# -gt 0 ]; do
  case "$1" in
    --drv) tier=b ;;
    --label) tier=a ;;
    --no-cache) no_cache=1 ;;
    --verbose | -v) verbose=1 ;;
    --json) json_out=1 ;;
    --field)
      shift
      if [ $# -eq 0 ]; then
        echo "nixos-eval-gate: --field needs a name" >&2
        exit 2
      fi
      field="$1"
      ;;
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

# What the answer is: `attr` (the tier's own attribute, today's behaviour), one
# named field of the tier-B answer set, or the whole set as JSON. It is part of
# the key, so a `--json` entry is never served to a scalar read.
selector=attr
if [ "$json_out" -eq 1 ] && [ -n "$field" ]; then
  echo "nixos-eval-gate: --json and --field are mutually exclusive" >&2
  exit 2
fi
if [ "$json_out" -eq 1 ] || [ -n "$field" ]; then
  if [ "$tier" != b ]; then
    echo "nixos-eval-gate: --field/--json need --drv (tier A answers the label only)" >&2
    exit 2
  fi
  if [ "$attr" != "$TIER_B_ATTR" ]; then
    echo "nixos-eval-gate: --field/--json name the fields of the standard tier-B answer set, so they cannot be combined with a custom attr" >&2
    exit 2
  fi
  if [ "$json_out" -eq 1 ]; then
    selector=json
  else
    case "$field" in
      label | drvPath | toplevel | name | system) selector="field:$field" ;;
      *)
        echo "nixos-eval-gate: unknown --field: $field (label, drvPath, toplevel, name, system)" >&2
        exit 2
        ;;
    esac
  fi
fi

note() { printf 'nixos-eval-gate: %s\n' "$*" >&2; }
debug() {
  if [ "$verbose" -eq 1 ]; then
    note "$*"
  fi
}

# The evaluator, overridable so the self-test can wrap it (a wrapper that answers
# `false` to the primop probe is the only way to exercise the fallback path).
NIX="${NIX:-nix}"

# ── the tier-B evaluation shape ─────────────────────────────────────────────
# Determinate ships a two-argument `builtins.parallel a b`: it forces `a` with
# the eval executor and returns `b`, so it is a forcing hint, not a value. Stock
# and patched upstream Nix have no such primop, so probe once, lazily — a cache
# hit never pays for the probe — and treat absent, `false` or an erroring probe
# alike: the plain shape, announced on --verbose, never an error.
parallel=""
detect_parallel() {
  local probe
  if [ -n "$parallel" ]; then
    return 0
  fi
  parallel=no
  case "${EVAL_GATE_PARALLEL:-auto}" in
    off)
      debug "tier B: plain shape (EVAL_GATE_PARALLEL=off)"
      return 0
      ;;
    auto | '') : ;;
    *) note "ignoring EVAL_GATE_PARALLEL=$EVAL_GATE_PARALLEL (auto|off)" ;;
  esac
  probe="$("$NIX" eval --expr 'builtins ? parallel' 2> /dev/null || true)"
  if [ "$probe" = true ]; then
    parallel=yes
  else
    debug "tier B: plain shape (builtins.parallel not available; eval-cores alone is a no-op for print.cc)"
  fi
}

# Split the tier-B attr into the configuration name and the rest of its path;
# non-zero when the attr is not under `nixosConfigurations.<host>.`, i.e. when
# there is no configuration to fan out from. Leaves $HOST and $REST set.
HOST=""
REST=""
split_attr() {
  HOST=""
  REST=""
  case "$attr" in
    nixosConfigurations.?*.*) : ;;
    *) return 1 ;;
  esac
  HOST="${attr#nixosConfigurations.}"
  HOST="${HOST%%.*}"
  REST="${attr#nixosConfigurations."$HOST".}"
  [ -n "$HOST" ] && [ -n "$REST" ]
}

# The `--apply` expression for tier B. $1 = parallel | plain. The parallel form
# forces every systemPackages drvPath (the fan-out `eval-cores` needs) and then
# returns the answer unchanged; the plain form is the same expression minus the
# fan-out, i.e. one single-threaded evaluation of the same value.
tier_b_expr() {
  local answer
  split_attr || return 1
  case "$selector" in
    json) answer="($TIER_B_FIELDS)" ;;
    field:*) answer="(($TIER_B_FIELDS).${selector#field:})" ;;
    *) answer="c.$REST" ;;
  esac
  if [ "$1" = parallel ]; then
    printf 'cs: let c = cs.%s; in builtins.parallel (map (p: p.drvPath) c.config.environment.systemPackages) %s' \
      "$HOST" "$answer"
  else
    printf 'cs: let c = cs.%s; in %s' "$HOST" "$answer"
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

  printf 'format\0v3\0'
  printf 'tier\0a\0'
  printf 'attr\0%s\0' "$attr"
  printf 'selector\0%s\0' "$selector"
  printf 'nix\0%s\0' "$("$NIX" --version)"
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

  printf 'format\0v3\0'
  printf 'tier\0b\0'
  printf 'attr\0%s\0' "$attr"
  printf 'selector\0%s\0' "$selector"
  printf 'nix\0%s\0' "$("$NIX" --version)"
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

# Hashes the key material and keeps it in $material_file: the proof record stores
# those exact bytes, so a cached answer can be re-derived without guessing which
# inputs the cache believed in. Cleaned up by the EXIT trap.
material_file=""
tree_key() {
  local key
  material_file="$(mktemp "${TMPDIR:-/tmp}/nixos-eval-gate.XXXXXXXX")" || return 1
  if [ "$tier" = b ]; then
    key_material_b > "$material_file" || return 1
  else
    key_material_a > "$material_file" || return 1
  fi
  key="$(sha256sum < "$material_file")" || return 1
  printf '%s\n' "${key%% *}"
}

# The live evaluation. Tier A is unchanged: one `--raw` of the label. Tier B runs
# the fan-out shape described in the header when `builtins.parallel` is there,
# and otherwise exactly today's plain `--raw …drvPath` — the fallback is never an
# error, only a slower and explicitly announced path. A whole-set answer
# (`--field`/`--json`) without the primop still costs one evaluation: the same
# expression minus the fan-out.
live_eval() {
  local expr qualifier
  if [ "$tier" = b ]; then
    detect_parallel
    if [ "$parallel" = yes ] && expr="$(tier_b_expr parallel)"; then
      if [ "$selector" = json ]; then
        qualifier=--json
      else
        qualifier=--raw
      fi
      debug "tier B: parallel shape (eval-cores=$TIER_B_CORES, answer=$selector)"
      (cd "$ROOT_REAL" && "$NIX" eval "$qualifier" --option eval-cores "$TIER_B_CORES" \
        --apply "$expr" .#nixosConfigurations)
      return
    fi
    if [ "$selector" = attr ]; then
      (cd "$ROOT_REAL" && "$NIX" eval --raw ".#$attr")
      return
    fi
    if expr="$(tier_b_expr plain)"; then
      # Same qualifier rule as the parallel branch: a JSON answer needs --json,
      # every other answer is a plain string and has to stay byte-identical to
      # what the fan-out shape prints — both shapes share one cache key.
      if [ "$selector" = json ]; then
        qualifier=--json
      else
        qualifier=--raw
      fi
      debug "tier B: plain shape, one evaluation of the whole answer set"
      (cd "$ROOT_REAL" && "$NIX" eval "$qualifier" --apply "$expr" .#nixosConfigurations)
      return
    fi
    note "cannot build the answer-set expression for $attr"
    return 1
  fi
  (cd "$ROOT_REAL" && "$NIX" eval --raw ".#$attr")
}

# The proof record beside the answer: what the cache believed in. Cheap (one
# `rev-parse`, one `ls-files -s`), written only on a miss. The file OIDs are
# git's own content hashes rather than sha256: a sha256sum per file would fork
# once per tracked file and cost more than the evaluation the gate exists to
# save. The material below carries the content of everything that differs from
# HEAD, so HEAD + these OIDs + that material re-derive the answer exactly.
write_record() {
  local answer="$1" tmp="$cache_dir/.$key.record.$$"
  {
    printf '# nixos-eval-gate proof record: what this cache entry believed in.\n'
    printf 'key %s\n' "$key"
    printf 'tier %s\n' "$tier"
    printf 'selector %s\n' "$selector"
    printf 'attr %s\n' "$attr"
    printf 'shape %s\n' "$(if [ "$tier" = b ] && [ "$parallel" = yes ]; then printf parallel; else printf plain; fi)"
    printf 'evaluator %s\n' "$("$NIX" --version)"
    printf 'head %s\n' "$(git -C "$REPO_ROOT" rev-parse HEAD 2> /dev/null || printf 'unknown')"
    printf 'answer %s\n' "$answer"
    printf 'stored_at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '# tracked files (git ls-files -s: mode, blob OID, path) — a superset\n'
    printf '# of the tier-A input set; the deciding inputs are the material below.\n'
    git -C "$REPO_ROOT" ls-files -s || printf 'unavailable\n'
    printf '# key material: the exact bytes the answer key was hashed from.\n'
    cat "$material_file" 2> /dev/null || printf 'unavailable\n'
  } > "$tmp" 2> /dev/null || {
    rm -f "$tmp" 2> /dev/null || true
    note "could not write the proof record in $cache_dir"
    return 0
  }
  mv -f "$tmp" "$cache_dir/$key.record" 2> /dev/null || {
    rm -f "$tmp" 2> /dev/null || true
    note "could not write the proof record in $cache_dir"
    return 0
  }
  debug "record $cache_dir/$key.record"
}

# The record's header only: the file list can be thousands of lines, so --verbose
# prints the part a human reads and points at the rest.
show_record() {
  if [ "$verbose" -eq 0 ]; then
    return 0
  fi
  if [ -f "$cache_dir/$key.record" ]; then
    sed -n '1,10p' "$cache_dir/$key.record" >&2
    note "proof record: the rest is in $cache_dir/$key.record"
  fi
}

cache_dir=""
if [ "$no_cache" -eq 0 ]; then
  cache_dir="$(resolve_cache_dir)" || cache_dir=""
fi

if [ -n "$cache_dir" ]; then
  trap 'if [ -n "${material_file:-}" ]; then rm -f "$material_file"; fi' EXIT
fi

key=""
if [ -n "$cache_dir" ]; then
  if key="$(tree_key)"; then
    debug "tier=$tier attr=$attr selector=$selector key=$key"
    entry="$cache_dir/$key"
    if [ -f "$entry" ]; then
      value=""
      value="$(< "$entry")"
      if [ "$selector" = json ]; then
        # A JSON answer spans lines, so the newline check below cannot apply; the
        # write is atomic, so a shape check is enough to reject a mangled file.
        case "$value" in
          '{'*'}') : ;;
          *)
            note "ignoring malformed cache entry $entry"
            value=""
            ;;
        esac
      else
        # $(< file) strips the trailing newline; an embedded one means a corrupt
        # write (the write is atomic, so this should not happen).
        case "$value" in
          '' | *$'\n'*)
            note "ignoring malformed cache entry $entry"
            value=""
            ;;
        esac
      fi
      if [ -n "$value" ]; then
        debug "hit $entry"
        show_record
        printf '%s\n' "$value"
        exit 0
      fi
    fi
    debug "miss $entry"
  else
    note "the input set cannot be hashed; running a live eval and caching nothing"
    key=""
  fi
else
  debug "cache disabled"
fi

if [ "$tier" = b ]; then
  # Probe in this shell, not inside $(live_eval)'s subshell: the proof record has
  # to report the shape the answer really came from.
  detect_parallel
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
    write_record "$value"
    show_record
  else
    rm -f "$tmp" 2> /dev/null || true
    note "could not write the cache entry in $cache_dir"
  fi
fi

printf '%s\n' "$value"
