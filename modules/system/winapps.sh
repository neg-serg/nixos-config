set -euo pipefail

if [ -f "$HOME/.config/winapps/winapps.conf" ]; then
  . "$HOME/.config/winapps/winapps.conf"
elif [ -f /etc/winapps/winapps.conf ]; then
  . /etc/winapps/winapps.conf
fi

APPS_DIR="@APPDIR@"
RDP_IP="${RDP_IP:-127.0.0.1}"
RDP_USER="${RDP_USER:-neg}"
RDP_DOMAIN="${RDP_DOMAIN:-}"
RDP_SCALE="${RDP_SCALE:-100}"
RDP_FLAGS="${RDP_FLAGS:-/network:auto /sound:auto /microphone:auto /gfx:avc444 /bpp:32}"
RDP_PASS="${RDP_PASS:-}"

if [ $# -eq 0 ]; then
  echo "Usage: winapps <app> [file]"
  echo "Available: $(@COREUTILS@/bin/ls "$APPS_DIR" | @COREUTILS_V2@/bin/sort)"
  exit 1
fi

APP="$1"
shift
FILE="${1:-}"
if [ ! -f "$APPS_DIR/$APP/info" ]; then
  echo "Unknown app: $APP" >&2
  exit 1
fi

. "$APPS_DIR/$APP/info"
ICON="$APPS_DIR/$APP/icon.svg"

if [ -n "$FILE" ]; then
  WIN_FILE=$(echo "$FILE" | @GNUSED@/bin/sed 's|'"$HOME"'|\\\\tsclient\\home|;s|/|\\|g;s|\\|\\\\|g')
  exec @FREERDP@/bin/xfreerdp \
    /v:"$RDP_IP" /u:"$RDP_USER" /p:"$RDP_PASS" \
    /cert:tofu +auto-reconnect +clipboard +home-drive \
    /scale:"$RDP_SCALE" /dynamic-resolution \
    /app:"program:$WIN_EXECUTABLE,cmd:\"$WIN_FILE\",icon:$ICON,name:$FULL_NAME"
else
  exec @FREERDP_V2@/bin/xfreerdp \
    /v:"$RDP_IP" /u:"$RDP_USER" /p:"$RDP_PASS" \
    /cert:tofu +auto-reconnect +clipboard +home-drive \
    /scale:"$RDP_SCALE" /dynamic-resolution \
    /app:"program:$WIN_EXECUTABLE,icon:$ICON,name:$FULL_NAME"
fi
