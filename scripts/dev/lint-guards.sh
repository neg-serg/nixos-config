#!/usr/bin/env bash
# Guard: Nix anti-patterns that used to be open-coded greps in the `lint`
# recipe. Rules run in table order; the first violation prints its explanation
# and the matching lines, then exits 1.
#
# Usage: lint-guards.sh [--list] [repo-root]
#   --list     print the rule names, one per line, and exit
#   repo-root  override the git top level (default: `git rev-parse`, else cwd)
#
# Env gates: EXECSTART_GUARD=1 and ESCAPEARGS_GUARD=1 enable the two optional
# rules (they were opt-in in the recipe too).
set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Rule table, one rule per line:
#   name@gate@scope@pattern@filter@stream@message
#     gate    env var that must equal 1 for the rule to run (empty = always on)
#     scope   path grep recurses into (`.` for the repo, `modules` for units)
#     filter  ERE; hits matching it are dropped (empty = keep every hit)
#     stream  where hits go: `out` (stdout) or `err` (stderr)
# `@` never appears in a field, so it is safe as the separator.
lint_rules() {
  cat <<'RULES'
with-pkgs-list@@.@with[[:space:]]+pkgs;[[:space:]]*\[@@out@Found discouraged pattern: use explicit pkgs.* items instead of `with pkgs; [...]`
target-pkgs-with-pkgs@@.@targetPkgs[[:space:]]*=[[:space:]]*pkgs:[[:space:]]*with[[:space:]]+pkgs@@out@Found discouraged pattern in FHS targetPkgs: avoid `with pkgs`
execstart-mkdir-touch-rm@@modules@Exec(Start|Stop)(Pre|Post)[[:space:]]*=.*(mkdir(\s+-p)?|install(\s+-d)?|touch|rm[[:space:]]+-rf?)@@out@Found ExecStartPre/ExecStart with mkdir/touch/rm. Declare managed files (force = true) or wrappers instead.
with-pkgs-lib@@.@\bwith[[:space:]]+pkgs\.lib\b@@out@Found discouraged pattern: avoid 'with pkgs.lib'; use explicit pkgs.lib.*
with-pkgs-namespace@@.@\bwith[[:space:]]+pkgs\.[A-Za-z0-9_-]+@pkgs\.lib\b@out@Found discouraged pattern: avoid 'with pkgs.<ns>'; reference explicit pkgs.<ns>.<item>
execstart-direct-pkgs-bin@EXECSTART_GUARD@modules@ExecStart\s*=\s*".*\$\{pkgs\.[^}]+\}/bin/@@out@Found ExecStart using direct ${pkgs.*}/bin path. Prefer:\n  let exe = lib.getExe' pkgs.<pkg> "<bin>"; in "${exe} …"
execstart-missing-escape-shell-args@ESCAPEARGS_GUARD@modules@ExecStart\s*=\s*let[^;]+in\s*"\$\{exe\}\s@escapeShellArgs@err@Found ExecStart pattern using ${exe} without lib.escapeShellArgs for args:
with-lib@@.@\bwith[[:space:]]+lib\b@@out@Found discouraged pattern: drop the bare `with lib;` line and qualify every lib symbol with the `lib.` prefix
RULES
}

# One matching pass for a rule: recurse from the rule scope with the shared
# Nix-file filters, then drop the hits its filter excludes.
scan_rule() {
  local scope="$1" pattern="$2" filter="$3" hits
  # A missing scope (e.g. `modules` in a scratch tree) has no hits; skipping it
  # keeps grep from printing "No such file or directory".
  [ -d "$scope" ] || return 0
  hits=$(grep -R -nE \
    --exclude-dir=.direnv --exclude-dir=result --exclude-dir=.git \
    --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' \
    -e "$pattern" -- "$scope" || true)
  if [ -n "$filter" ] && [ -n "$hits" ]; then
    hits=$(printf '%s\n' "$hits" | grep -vE -e "$filter" || true)
  fi
  printf '%s' "$hits"
}

# Structural rule the line-based table cannot express: a raw
# `Restart = "on-failure";` inside a `systemd.user.services` block means the
# restart policy was hand-rolled — it must come from the `restartOnFailure`
# preset of lib/systemd-user.nix (see modules/AGENTS.md). Grep cannot see block
# nesting, so this one walks the braces with awk over the files that declare
# user services at all. The system-level twin is
# `scan_restart_preset_system` below.
scan_restart_preset() {
  local hits
  hits=$(
    grep -R -lE --exclude-dir=.direnv --exclude-dir=result --exclude-dir=.git \
      --include='*.nix' 'systemd\.user\.services' modules hosts 2> /dev/null |
      xargs -r awk '
        /systemd\.user\.services/ { inblk = 1 }
        inblk {
          opens = gsub(/\{/, "{")
          closes = gsub(/\}/, "}")
          depth += opens - closes
          if ($0 ~ /^[[:space:]]*Restart[[:space:]]*=[[:space:]]*"on-failure";/) {
            printf "%s:%d:%s\n", FILENAME, FNR, $0
          }
          if (depth <= 0 && opens + closes > 0) inblk = 0
        }
      ' || true
  )
  if [ -n "$hits" ]; then
    printf '%s\n' 'Found a hand-rolled restart policy in systemd.user.services: use the `restartOnFailure` preset (lib/systemd-user.nix); keep the delay as a caller-side RestartSec.' >&2
    printf '%s\n' "$hits" >&2
    exit 1
  fi
}

# Symmetric to `scan_restart_preset`: the same raw `Restart = "on-failure";`
# inside a `systemd.services` block is hand-rolled too — the system twin
# `mkSystemService` takes the same `restartOnFailure` preset (lib/systemd-user.nix).
scan_restart_preset_system() {
  local hits
  hits=$(
    grep -R -lE --exclude-dir=.direnv --exclude-dir=result --exclude-dir=.git \
      --include='*.nix' 'systemd\.services' modules hosts 2> /dev/null |
      xargs -r awk '
        /systemd\.services/ { inblk = 1 }
        inblk {
          opens = gsub(/\{/, "{")
          closes = gsub(/\}/, "}")
          depth += opens - closes
          if ($0 ~ /^[[:space:]]*Restart[[:space:]]*=[[:space:]]*"on-failure";/) {
            printf "%s:%d:%s\n", FILENAME, FNR, $0
          }
          if (depth <= 0 && opens + closes > 0) inblk = 0
        }
      ' || true
  )
  if [ -n "$hits" ]; then
    printf '%s\n' 'Found a hand-rolled restart policy in systemd.services: use the `restartOnFailure` preset (lib/systemd-user.nix); keep the delay as a caller-side RestartSec.' >&2
    printf '%s\n' "$hits" >&2
    exit 1
  fi
}

list_only=0
repo_arg=""
for arg in "$@"; do
  case "$arg" in
    --list) list_only=1 ;;
    *) repo_arg="$arg" ;;
  esac
done

if [ "$list_only" -eq 1 ]; then
  while IFS= read -r rule; do
    printf '%s\n' "${rule%%@*}"
  done < <(lint_rules)
  printf 'restart-preset\n'
  printf 'restart-preset-system\n'
  exit 0
fi

REPO_ROOT="$(repo_root "$repo_arg")"
cd "$REPO_ROOT" || exit 1

while IFS='@' read -r _name gate scope pattern filter stream message; do
  if [ -n "$gate" ] && [ "${!gate:-}" != "1" ]; then
    continue
  fi
  hits=$(scan_rule "$scope" "$pattern" "$filter")
  if [ -n "$hits" ]; then
    printf '%b\n' "$message" >&2
    if [ "$stream" = "err" ]; then
      printf '%s\n' "$hits" >&2
    else
      printf '%s\n' "$hits"
    fi
    exit 1
  fi
done < <(lint_rules)

scan_restart_preset
scan_restart_preset_system

exit 0
