set -euo pipefail

# Fetch trackers list directly (no local checkout required)
TRACKERS_URL="${TRACKERS_URL:-https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt}"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Fetch with curl from the nix store: the unit PATH is minimal and
# contains no wget/curl, so the tools cannot be looked up by name.
if ! @curl@ -fsSL "$TRACKERS_URL" -o "$tmp"; then
  echo "Failed to fetch trackers list with curl: $TRACKERS_URL" >&2
  exit 1
fi

# Optional connection args for transmission-remote
# TRANSMISSION_REMOTE may be a host, host:port or full RPC URL
# TRANSMISSION_AUTH may be "user:pass" if auth is enabled
args=()
if [ -n "${TRANSMISSION_REMOTE:-}" ]; then
  args+=("$TRANSMISSION_REMOTE")
fi
if [ -n "${TRANSMISSION_AUTH:-}" ]; then
  args+=(--auth "$TRANSMISSION_AUTH")
fi

# Probe connection (non-fatal)
@transmissionRemote@ "${args[@]}" -si > /dev/null 2>&1 || true

# Add each tracker to all torrents; ignore duplicates/errors
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac
  case "$line" in *://*) ;; *) continue ;; esac
  @transmissionRemote@ "${args[@]}" -t all -td "$line" > /dev/null 2>&1 || true
done < "$tmp"
