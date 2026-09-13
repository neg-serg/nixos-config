set -euo pipefail
amixer_bin=@alsaUtils@/bin/amixer

# Find HDSPe card
found=""
for card in "RMEAIO" "HDSPeAIO" "HDSPe" "AIO" "RME_AIO" "HDSPe24048964"; do
  if $amixer_bin -c "$card" info > /dev/null 2>&1; then
    found="$card"
    break
  fi
done
if [ -z "$found" ]; then
  # Fallback: scan all cards for HDSPe
  for card in $($amixer_bin cards 2> /dev/null | grep -ioE 'card[0-9]+|HDSPe[0-9]+' | tr -d ','); do
    if $amixer_bin -c "$card" info 2> /dev/null | grep -qi "HDSPe\|RME.*AIO"; then
      found="$card"
      break
    fi
  done
fi

[ -n "$found" ] || exit 0

# Set all Chn N controls to unity gain (64)
# AIO Pro has up to 16 output channels at single speed
for chn in $(seq 1 16); do
  $amixer_bin -c "$found" set "Chn $chn" 64 > /dev/null 2>&1 || true
done
