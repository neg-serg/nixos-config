#!/usr/bin/env bash
set -euo pipefail

# Reset Nextcloud + PostgreSQL on telfir to a clean state
# - Clears Nextcloud config for a fresh maintenance:install run
# - Ensures datadir and admin password file for services.nextcloud
# - Drops PostgreSQL DB/role for Nextcloud so the module can recreate them
# - Restarts nextcloud-setup and nextcloud-update-db units

DATADIR=${DATADIR:-/zero/sync/nextcloud}
ADMIN_PASS=${ADMIN_PASS:-Admin123!ChangeMe}
DB_NAME=${DB_NAME:-nextcloud}
DB_USER=${DB_USER:-nextcloud}

echo "nextcloud-reset-pg: using datadir=${DATADIR}, db=${DB_NAME}, user=${DB_USER}" >&2

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "nextcloud-reset-pg: must be run as root (use sudo)" >&2
  exit 1
fi

stop_unit() {
  local u=$1
  if systemctl list-units --type=service --all "$u" >/dev/null 2>&1; then
    systemctl stop "$u" 2>/dev/null || true
  fi
}

echo "nextcloud-reset-pg: stopping Nextcloud-related units..." >&2
stop_unit nextcloud-setup.service
stop_unit nextcloud-update-db.service
stop_unit nextcloud.service
stop_unit phpfpm-nextcloud.service

echo "nextcloud-reset-pg: preparing datadir..." >&2
mkdir -p "${DATADIR}/config" "${DATADIR}/data"

rm -f "${DATADIR}/config/config.php" "${DATADIR}/config/CAN_INSTALL"

printf '%s' "${ADMIN_PASS}" > "${DATADIR}/adminpass"

chown -R nextcloud:nextcloud "${DATADIR}"
chmod 750 "${DATADIR}" "${DATADIR}/config" "${DATADIR}/data"
chmod 600 "${DATADIR}/adminpass"

echo "nextcloud-reset-pg: resetting PostgreSQL database and role..." >&2

if systemctl list-units --type=service --all postgresql.service >/dev/null 2>&1; then
  systemctl start postgresql.service
fi

sudo -u postgres psql -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS \"${DB_NAME}\";" || true
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "DROP ROLE IF EXISTS \"${DB_USER}\";" || true

echo "nextcloud-reset-pg: starting postgresql.service..." >&2
systemctl start postgresql.service

echo "nextcloud-reset-pg: running nextcloud-setup.service..." >&2
systemctl restart nextcloud-setup.service || {
  echo "nextcloud-reset-pg: nextcloud-setup.service failed; check logs:" >&2
  echo "  journalctl -xeu nextcloud-setup.service" >&2
  exit 1
}

echo "nextcloud-reset-pg: running nextcloud-update-db.service..." >&2
systemctl restart nextcloud-update-db.service || {
  echo "nextcloud-reset-pg: nextcloud-update-db.service failed; check logs:" >&2
  echo "  journalctl -xeu nextcloud-update-db.service" >&2
}

echo "nextcloud-reset-pg: status of key units:" >&2
systemctl --no-pager --full status \
  nextcloud-setup.service \
  nextcloud-update-db.service \
  postgresql.service \
  phpfpm-nextcloud.service \
  caddy.service || true

echo
echo "Nextcloud reset complete."
echo "Check URLs:"
echo "  status:  curl -k -s -o /dev/null -w '%{http_code}\\n' https://telfir/status.php"
echo "  login:   curl -k -s -o /dev/null -w '%{http_code}\\n' https://telfir/index.php/login"
echo
echo "Login in browser:"
echo "  https://telfir"
echo "  user:     admin"
echo "  password: ${ADMIN_PASS}"
echo
echo "To reset admin password later:"
echo "  sudo -u nextcloud nextcloud-occ user:resetpassword admin"

