#!/usr/bin/env bash
# @script
# purpose: Copy user data from Floorp browser profile into a Zen browser profile without overwriting Salt-managed Zen files. One-shot operation guarded by a marker stamp.
#


set -euo pipefail

usage() {
  cat <<'EOF'
Usage: migrate-floorp-to-zen-profile.sh --floorp-profile <path> --zen-profile <path> --stamp <path>

Copy user data from a Floorp profile into a Zen profile without overwriting the
Salt-managed Zen files. The command is intentionally one-shot and should be
guarded by a marker file passed via --stamp.
EOF
}

floorp_profile=""
zen_profile=""
stamp=""

while (($# > 0)); do
  case "$1" in
    --floorp-profile)
      floorp_profile="${2:-}"
      shift 2
      ;;
    --zen-profile)
      zen_profile="${2:-}"
      shift 2
      ;;
    --stamp)
      stamp="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$floorp_profile" || -z "$zen_profile" || -z "$stamp" ]]; then
  usage >&2
  exit 2
fi

if [[ ! -d "$floorp_profile" ]]; then
  printf 'Floorp profile not found: %s\n' "$floorp_profile" >&2
  exit 1
fi

if [[ ! -d "$zen_profile" ]]; then
  printf 'Zen profile not found: %s\n' "$zen_profile" >&2
  exit 1
fi

mkdir -p "$(dirname "$stamp")"

copy_path() {
  local relpath="$1"
  local src="$floorp_profile/$relpath"
  local dst="$zen_profile/$relpath"
  if [[ -e "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
  fi
}

# Keep the migration limited to user data that is portable between Firefox
# derivatives. Zen-specific managed files, extensions, and UI assets are
# deployed separately by Salt.
for relpath in \
  places.sqlite \
  favicons.sqlite \
  cookies.sqlite \
  formhistory.sqlite \
  permissions.sqlite \
  content-prefs.sqlite \
  extension-settings.json \
  containers.json \
  sessionstore.jsonlz4 \
  xulstore.json \
  handlers.json \
  key4.db \
  cert9.db \
  logins.json \
  pkcs11.txt \
  persdict.dat \
  search.json.mozlz4 \
  bookmarkbackups \
  sessionstore-backups \
  storage
do
  copy_path "$relpath"
done

touch "$stamp"
