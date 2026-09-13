set -euo pipefail

# Check if HDSPe card is present first — avoid waiting if hardware absent
found=""
for card in "RMEAIO" "HDSPeAIO" "HDSPe" "AIO" "RME_AIO" "HDSPe24048964"; do
  if amixer -c "$card" info > /dev/null 2>&1; then
    found="$card"
    break
  fi
done
[ -n "$found" ] || exit 0

# Wait up to 20s for the RME sink: wireplumber recreates the ALSA node on
# every restart, and the sink appears a moment after wireplumber is up.
# Without this wait, the pw-link calls below fail and the loopback stream
# stays auto-linked to the analog pair (AUX0/1) → no sound on AES monitors.
# Pure bash matching (no grep) — the unit PATH only carries pipewire/coreutils.
for _ in $(seq 1 40); do
  if [[ "$(wpctl status 2> /dev/null)" == *"RME AIO Pro"* ]]; then
    break
  fi
  sleep 0.5
done

status="$(wpctl status 2> /dev/null || true)"

# Find HDSPe hardware sink and game-stereo virtual sink
hdspe_sink_id="$(echo "$status" | sed -n '/RME AIO Pro.*Pro/{s/^[^0-9]*\([0-9]\+\).*/\1/p;q}')"
# Match the SINK line only: the loopback's stream "playback.game-stereo"
# appears earlier in wpctl status, and sed -q would grab its id (46) instead
# of the sink (47). Require the "Audio/Sink" marker on the same line.
game_sink_id="$(echo "$status" | sed -n '/game-stereo.*Audio\/Sink/{s/^[^0-9]*\([0-9]\+\).*/\1/p;q}')"

# Route game-stereo → HDSPe AUX2/AUX3 (AES/EBU): the user's monitors are
# on AES, the analog RCA pair (AUX0/1) is unused; this script owns the
# mapping.
if [ -n "$hdspe_sink_id" ] && [ -n "$game_sink_id" ]; then
  wpctl set-default "$game_sink_id" || true
  # WirePlumber auto-links new stereo streams to the RME's FIRST channels
  # (AUX0/1 = analog). Drop those stray links so the loopback feeds only
  # the AES pair, then connect virtual sink playback to HDSPe AES (AUX2/3).
  pw-link -d playback.game-stereo:output_FL alsa_output.pci-0000_05_00.0.pro-output-0:playback_AUX0 2> /dev/null || true
  pw-link -d playback.game-stereo:output_FR alsa_output.pci-0000_05_00.0.pro-output-0:playback_AUX1 2> /dev/null || true
  pw-link playback.game-stereo:output_FL alsa_output.pci-0000_05_00.0.pro-output-0:playback_AUX2 2> /dev/null || true
  pw-link playback.game-stereo:output_FR alsa_output.pci-0000_05_00.0.pro-output-0:playback_AUX3 2> /dev/null || true
fi
