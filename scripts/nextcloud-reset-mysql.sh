#!/usr/bin/env bash
set -euo pipefail

# Reset Nextcloud + MariaDB/MySQL on telfir to a clean state
# - Clears Nextcloud config for a fresh maintenance:install run
# - Ensures datadir and admin password file for services.nextcloud
# - Attempts to drop and recreate the Nextcloud database/user (best-effort)
# - Runs a fresh maintenance:install as user nextcloud
# - Optionally restarts nextcloud-update-db and prints detailed diagnostics

DATADIR=${DATADIR:-/zero/sync/nextcloud}
ADMIN_PASS=${ADMIN_PASS:-Admin123!ChangeMe}
DB_NAME=${DB_NAME:-nextcloud}
DB_USER=${DB_USER:-nextcloud}
DB_HOST=${DB_HOST:-localhost:/run/mysqld/mysqld.sock}
DB_USER_PASS=${DB_USER_PASS:-""}
DB_ROOT_USER=${DB_ROOT_USER:-root}
OCC_BIN=${OCC_BIN:-/run/current-system/sw/bin/nextcloud-occ}

log() {
  echo "nextcloud-reset-mysql: $*" >&2
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  log "must be run as root (use sudo)"
  exit 1
fi

if [[ ! -x "$OCC_BIN" ]]; then
  log "occ binary not found at $OCC_BIN"
  log "Ensure services.nextcloud is enabled and the system is rebuilt, then rerun."
  exit 1
fi

log "using datadir=${DATADIR}, db=${DB_NAME}, user=${DB_USER}, host=${DB_HOST}"

stop_unit() {
  local u=$1
  if systemctl list-units --type=service --all "$u" >/dev/null 2>&1; then
    systemctl stop "$u" 2>/dev/null || true
  fi
}

log "stopping Nextcloud-related units..."
stop_unit nextcloud-setup.service
stop_unit nextcloud-update-db.service
stop_unit nextcloud.service
stop_unit phpfpm-nextcloud.service

log "preparing datadir..."
mkdir -p "${DATADIR}/config" "${DATADIR}/data"

log "removing old Nextcloud config.php and CAN_INSTALL (if any)..."
rm -f "${DATADIR}/config/config.php" "${DATADIR}/config/CAN_INSTALL"

log "writing admin password file..."
printf '%s' "${ADMIN_PASS}" > "${DATADIR}/adminpass"

log "fixing ownership and permissions on datadir..."
chown -R nextcloud:nextcloud "${DATADIR}"
chmod 750 "${DATADIR}" "${DATADIR}/config" "${DATADIR}/data"
chmod 600 "${DATADIR}/adminpass"

log "ensuring mysql.service is running..."
if systemctl list-units --type=service --all mysql.service >/dev/null 2>&1; then
  systemctl start mysql.service
else
  log "WARNING: mysql.service not found; Nextcloud DB may not be available."
fi

if command -v mysql >/dev/null 2>&1; then
  log "dropping and recreating Nextcloud database and user (best-effort)..."
  if ! mysql -u "${DB_ROOT_USER}" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;"; then
    log "WARNING: failed to drop database ${DB_NAME} as ${DB_ROOT_USER}; continuing."
  fi
  if ! mysql -u "${DB_ROOT_USER}" -e "DROP USER IF EXISTS '${DB_USER}'@'localhost';"; then
    log "WARNING: failed to drop user ${DB_USER}@localhost as ${DB_ROOT_USER}; continuing."
  fi
  if ! mysql -u "${DB_ROOT_USER}" -e "CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
    log "ERROR: failed to create database ${DB_NAME} as ${DB_ROOT_USER}."
    log "Please run manually and share any errors:"
    log "  mysql -u ${DB_ROOT_USER} -e 'CREATE DATABASE \\\`${DB_NAME}\\\\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'"
    exit 1
  fi
  if ! mysql -u "${DB_ROOT_USER}" -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_USER_PASS}';"; then
    log "ERROR: failed to create user ${DB_USER}@localhost as ${DB_ROOT_USER}."
    log "Please run manually and share any errors:"
    log "  mysql -u ${DB_ROOT_USER} -e \"CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_USER_PASS}';\""
    exit 1
  fi
  if ! mysql -u "${DB_ROOT_USER}" -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;"; then
    log "ERROR: failed to grant privileges on ${DB_NAME} to ${DB_USER}@localhost."
    log "Please run manually and share any errors:"
    log "  mysql -u ${DB_ROOT_USER} -e \"GRANT ALL PRIVILEGES ON \\\`${DB_NAME}\\\\\`.* TO '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;\""
    exit 1
  fi
else
  log "mysql client not found in PATH; skipping DB reset."
fi

log "running fresh maintenance:install as user nextcloud..."
set +e
sudo -u nextcloud "$OCC_BIN" maintenance:install \
  --admin-user "admin" \
  --admin-pass "${ADMIN_PASS}" \
  --data-dir "${DATADIR}/data" \
  --database "mysql" \
  --database-host "${DB_HOST}" \
  --database-name "${DB_NAME}" \
  --database-user "${DB_USER}" \
  --database-pass "${DB_USER_PASS}"
install_rc=$?
set -e

if [[ $install_rc -ne 0 ]]; then
  log "ERROR: maintenance:install failed with exit code ${install_rc}."
  log "For diagnostics, collect and share:"
  log "  journalctl -xeu nextcloud-setup.service"
  log "  sudo -u nextcloud \"$OCC_BIN\" maintenance:install --help"
  log "  sudo -u nextcloud \"$OCC_BIN\" status || echo 'occ status failed'"
  exit $install_rc
fi

log "maintenance:install reported success; setting trusted_domains..."
if ! sudo -u nextcloud "$OCC_BIN" config:system:set trusted_domains 0 --value="telfir"; then
  log "WARNING: failed to set trusted_domains via occ; you may need to run this manually:"
  log "  sudo -u nextcloud \"$OCC_BIN\" config:system:set trusted_domains 0 --value=\"telfir\""
fi

log "optionally restarting nextcloud-update-db.service to apply DB maintenance..."
if systemctl list-units --type=service --all nextcloud-update-db.service >/dev/null 2>&1; then
  if ! systemctl restart nextcloud-update-db.service; then
    log "WARNING: nextcloud-update-db.service failed. For diagnostics, run:"
    log "  journalctl -xeu nextcloud-update-db.service"
  fi
fi

log "status snapshots:"
systemctl --no-pager --full status \
  nextcloud-setup.service \
  nextcloud-update-db.service \
  mysql.service \
  phpfpm-nextcloud.service \
  caddy.service || true

log "datadir ownership/permissions snapshot:"
ls -ld "${DATADIR}" "${DATADIR}/config" "${DATADIR}/data" || true
ls -l "${DATADIR}/adminpass" || true

log "checking occ status as user nextcloud..."
if ! sudo -u nextcloud "$OCC_BIN" status; then
  log "WARNING: 'sudo -u nextcloud $OCC_BIN status' failed; include this output in bug reports."
fi

echo
echo "Nextcloud MySQL reset sequence finished."
echo "If something still fails, please collect and share:"
echo "  journalctl -xeu nextcloud-setup.service"
echo "  journalctl -xeu nextcloud-update-db.service"
echo "  sudo -u nextcloud \"$OCC_BIN\" status"
echo "  ls -ld \"${DATADIR}\" \"${DATADIR}/config\" \"${DATADIR}/data\""
echo "  ls -l \"${DATADIR}/adminpass\""
echo
echo "After a successful reset, you can test via:"
echo "  curl -k -s -o /dev/null -w '%{http_code}\\n' https://telfir/status.php"
echo "  curl -k -s -o /dev/null -w '%{http_code}\\n' https://telfir/index.php/login"
echo
echo "Login in browser:"
echo "  https://telfir"
echo "  user:     admin"
echo "  password: ${ADMIN_PASS}"
echo
echo "To reset admin password later:"
echo "  sudo -u nextcloud \"$OCC_BIN\" user:resetpassword admin"
