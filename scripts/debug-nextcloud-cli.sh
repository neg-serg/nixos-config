#!/usr/bin/env bash
set -euo pipefail

OUT="/tmp/nextcloud-cli-debug-$(date +%s).log"
exec >"$OUT" 2>&1

log() { printf '=== %s ===\n' "$1"; }

log "env"
echo "user: $(id -un) ($(id -u)), homedir: $HOME"
echo "PATH: $PATH"

log "nextcloudcmd version"
nextcloudcmd --version || true

log "secrets"
ls -l /run/user/1000/secrets || true
if [ -f /run/user/1000/secrets/nextcloud-cli.env ]; then
  grep . /run/user/1000/secrets/nextcloud-cli.env || true
fi

log "certs"
ls -l /etc/ssl/certs | grep -i caddy || true
ls -l /etc/nixos/certs || true

log "systemd units"
systemctl --user list-unit-files | grep nextcloud-sync || true
systemctl --user list-timers | grep nextcloud-sync || true
systemctl --user status nextcloud-sync.service || true
systemctl --user status nextcloud-sync.timer || true

log "manual run"
if [ -f /run/user/1000/secrets/nextcloud-cli.env ]; then
  source /run/user/1000/secrets/nextcloud-cli.env
  export NC_USER=neg NC_PASSWORD="${NEXTCLOUD_PASS:-}"
  mkdir -p /tmp/nc-debug
  SSL_CERT_FILE=/etc/nixos/certs/caddy-root.crt \
    nextcloudcmd --logdebug --non-interactive /tmp/nc-debug https://telfir || true
fi

log "journal"
journalctl --user -u nextcloud-sync.service -n 100 --no-pager || true

log "done"
echo "Log saved to $OUT"
