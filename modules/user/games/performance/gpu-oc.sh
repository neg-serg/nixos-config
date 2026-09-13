set -e
# Pick the AMD dGPU whose pp_od_clk_voltage exposes VDDGFX_OFFSET (the
# RX 9070 XT). The Granite Ridge iGPU only has a bare SCLK interface and
# rejects 'vo' writes; card index varies with probe order.
DEV=""
for c in /sys/class/drm/card*/device/pp_od_clk_voltage; do
  [ -r "$c" ] || continue
  if grep -q "VDDGFX_OFFSET" "$c" 2> /dev/null; then
    DEV="$c"
    break
  fi
done
[ -n "$DEV" ] || {
  echo "gpu-oc: no overclockable AMD GPU (VDDGFX_OFFSET) found" >&2
  exit 1
}
# Wait for the GPU sysfs interface to appear (amdgpu probe may lag boot)
for i in $(seq 1 30); do
  [ -w "$DEV" ] && break
  sleep 1
done
[ -w "$DEV" ] || {
  echo "gpu-oc: $DEV not writable after 30s" >&2
  exit 1
}
case "$1" in
  reset)
    echo "r" > "$DEV"
    echo "c" > "$DEV"
    ;;
  *)
    SCLK="${1:?usage: gpu-oc <sclk-offset> <vddgfx-offset>|reset}"
    VDDG="${2:?usage: gpu-oc <sclk-offset> <vddgfx-offset>|reset}"
    echo "s $SCLK" > "$DEV"
    echo "vo $VDDG" > "$DEV"
    echo "c" > "$DEV"
    ;;
esac
