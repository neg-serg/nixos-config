#!/usr/bin/env bash
set -euo pipefail

OUT="/tmp/nextcloud-cli-debug-$(date +%s).log"
exec >"$OUT" 2>&1

log() { printf '=== %s ===\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

log "env"
echo "user: $(id -un) ($(id -u)), homedir: $HOME"
echo "PATH: $PATH"

log "nextcloudcmd version"
nextcloudcmd --version || true

log "secrets"
ls -l /run/user/1000/secrets || true
stat /run/user/1000/secrets/nextcloud-cli.env || true
stat /run/user/1000/secrets/nextcloud-cli-wrk.env || true

log "certs"
ls -l /etc/ssl/certs | grep -i caddy || true
ls -l /etc/nixos/certs || true

log "systemd units"
systemctl --user list-unit-files | grep nextcloud-sync || true
systemctl --user list-timers | grep nextcloud-sync || true
systemctl --user status nextcloud-sync.service || true
systemctl --user status nextcloud-sync.timer || true
systemctl --user status nextcloud-sync-wrk.service || true
systemctl --user status nextcloud-sync-wrk.timer || true

log "sync dirs"
ls -ld "$HOME/sync" "$HOME/sync/telfir" "$HOME/sync/wrk" 2>/dev/null || true

log "manual run"
manual_sync() {
  local profile="$1" envfile="$2" localdir="$3" fallback_url="$4"
  [ -f "$envfile" ] || { echo "skip $profile: no env file $envfile"; return; }
  set -a
  # shellcheck disable=SC1090
  source "$envfile"
  set +a
  local url="${NEXTCLOUD_URL:-$fallback_url}"
  local user="${NEXTCLOUD_USER:-${NC_USER:-}}"
  local pass="${NEXTCLOUD_PASS:-${NC_PASSWORD:-}}"
  mkdir -p "$localdir"
  if [ -z "$url" ] || [ -z "$user" ]; then
    echo "skip $profile: url/user missing (url='$url', user='$user')"
    return
  fi
  export NC_USER="$user"
  if [ -n "$pass" ]; then
    export NC_PASSWORD="$pass"
  fi
  echo "running $profile sync to $url -> $localdir"
  SSL_CERT_FILE=${SSL_CERT_FILE:-/etc/nixos/certs/caddy-root.crt} \
    nextcloudcmd --logdebug --non-interactive --silent "$localdir" "$url" || true
}

if have nextcloudcmd; then
  manual_sync "primary" /run/user/1000/secrets/nextcloud-cli.env /tmp/nc-debug https://telfir/remote.php/dav/files/neg/
  manual_sync "work" /run/user/1000/secrets/nextcloud-cli-wrk.env /tmp/nc-debug-wrk ""
fi

log "journal"
journalctl --user -u nextcloud-sync.service -n 100 --no-pager || true
journalctl --user -u nextcloud-sync-wrk.service -n 100 --no-pager || true

log "done"
echo "Log saved to $OUT"
