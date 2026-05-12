set -euo pipefail
# Hint: SteamVR AppID is 250820
steam -applaunch 250820 &
STEAM_PID=$!

# Wait for VRCompositor to come up (up to 60s), then for it to exit
tries=60
while ! pgrep -f -u "$USER" -x vrcompositor > /dev/null 2>&1; do
  sleep 1
  tries=$((tries - 1))
  if [ "$tries" -le 0 ]; then
    break
  fi
done

# Poll until VR compositor fully exits
while pgrep -f -u "$USER" -x vrcompositor > /dev/null 2>&1; do
  sleep 2
done

# Give Steam a moment to settle
sleep 1
wait "$STEAM_PID" || true
