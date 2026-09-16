#!/bin/sh
# Shared helpers for the scripts in this directory. Source it with the caller's
# own path, so the helpers can print its header and prefix diagnostics with its
# name — zsh sets $0 to the function name inside functions (FUNCTION_ARGZERO):
#
#   LOCALBIN_SELF=$0 . "$(dirname "$0")/_localbin.sh"
#
# modules/user/nix-maid/cli/local-bin.nix installs every regular file in bin/
# into ~/.local/bin, so the helper always sits next to its callers. The prefix
# assignment cannot be reused as the storage name: zsh drops it when the source
# command returns, so the value is copied into LOCALBIN_PATH (which persists in
# every shell, since the sourced file runs in the caller's shell).
LOCALBIN_PATH=${LOCALBIN_SELF:-$0}
PROG=${LOCALBIN_PATH##*/}

# need CMD — warn (and continue, status 0) when an optional tool is missing.
need() {
  command -v "$1" > /dev/null 2>&1 && return 0
  printf '%s: missing %s\n' "$PROG" "$1" >&2
}

# require CMD — missing tool is fatal: "<name>: missing dependency: CMD".
require() {
  command -v "$1" > /dev/null 2>&1 || die "missing dependency: $1"
}

# die [MSG...] — report "<name>: MSG" on stderr and exit 1.
die() {
  printf '%s: %s\n' "$PROG" "$*" >&2
  exit 1
}

# usage_from_header FIRST LAST — print comment lines FIRST..LAST of the caller.
usage_from_header() {
  sed -n "$1,${2}p" "$LOCALBIN_PATH" | sed 's/^# \{0,1\}//'
}

# help_from_header FIRST LAST "$@" — print the header and exit 0 on -h/--help.
help_from_header() {
  case "${3:-}" in
    -h | --help)
      usage_from_header "$1" "$2"
      exit 0
      ;;
  esac
}

# help_dispatch "$@" — run `usage` for -h/--help/help/? (case-form callers).
help_dispatch() {
  case "${1:-}" in
    -h | --help | help | \?) usage ;;
  esac
}
