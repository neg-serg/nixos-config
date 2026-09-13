set -euo pipefail
P=@PATH@
S=@SIZEGIB@
if [ ! -f "$P" ]; then
  echo "[swapfile-ensure] Creating swapfile $P (@SIZEGIB_V2@G)"
  umask 077
  mkdir -p "$(dirname "$P")"
  if command -v fallocate > /dev/null 2>&1; then
    fallocate -l "@SIZEGIB_V3@G" "$P"
  else
    # Fallback: allocate by writing zeros (slower but portable)
    dd if=/dev/zero of="$P" bs=1G count="$S" status=none
  fi
  chmod 600 "$P"
  chown root:root "$P"
  mkswap -f "$P"
else
  echo "[swapfile-ensure] Swapfile already exists: $P (skipping)"
fi
