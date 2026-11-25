#!/usr/bin/env bash
# Recover the RME HDSPe from a stuck playback DMA.
#
# Symptom: the card reports `state: RUNNING` while `hw_ptr` and the interrupt
# counter stay frozen, CamillaDSP starves ("waited 1s but only got 0 of 4096
# bytes, skipping chunk") and the monitors are silent even though PipeWire is
# writing the AES ports — measurable on `alsa_output…:monitor_AUX*` while a tone
# plays. A warm reboot may not clear it; only a PCIe function reset does.
#
# Order matters twice: no client may hold the device across the reset, and the
# mixer init has to follow it, because the driver zeroes the hardware mixer on
# load (a rebind alone leaves the AES pair silent).
#
# Run as the user, not as root: the graph units are `--user`, and only the PCIe
# and system-unit steps escalate.
set -euo pipefail

USER_STOP="camilladsp.service pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service"
USER_START="pipewire.socket pipewire-pulse.socket wireplumber.service pipewire.service pipewire-pulse.service"

slot=$(find /sys/bus/pci/drivers/snd_hdspe -maxdepth 1 -name '0000:*' -printf '%f\n' 2> /dev/null | head -1)
if [ -z "$slot" ]; then
  echo "hdspe-reset: no card is bound to snd_hdspe" >&2
  exit 1
fi
echo "hdspe-reset: card at PCI $slot"

echo "hdspe-reset: stopping the pipewire graph"
# shellcheck disable=SC2086  # a literal list of unit names, split on purpose
systemctl --user stop $USER_STOP || true

echo "hdspe-reset: PCIe unbind -> reset -> bind"
# shellcheck disable=SC2086
sudo sh -c "echo $slot > /sys/bus/pci/drivers/snd_hdspe/unbind
            sleep 1
            echo 1 > /sys/bus/pci/devices/$slot/reset
            sleep 1
            echo $slot > /sys/bus/pci/drivers/snd_hdspe/bind"

echo "hdspe-reset: re-initialising the hardware mixer"
sudo systemctl restart hdspe-init-mixer.service

echo "hdspe-reset: starting the graph"
# shellcheck disable=SC2086
systemctl --user start $USER_START
systemctl --user start camilladsp.service

# hw_ptr only moves while a stream feeds the device, so the check plays a short
# tone into the default sink and compares the counter around it. The card index
# is read after the rebind: it is not guaranteed to survive the reset.
card=$(awk '/HDSPe|RME.*AIO/ { gsub(/[^0-9]/, "", $1); print $1; exit }' /proc/asound/cards 2> /dev/null || true)
status="/proc/asound/card${card:-0}/pcm0p/sub0/status"
hw_ptr() { awk '/hw_ptr/ { print $3 }' "$status" 2> /dev/null || true; }

before=$(hw_ptr)
timeout 3 speaker-test -D pipewire -c 2 -t sine -f 440 -l 1 > /dev/null 2>&1 || true
after=$(hw_ptr)

if [ "${after:-0}" -gt "${before:-0}" ]; then
  echo "hdspe-reset: OK — hw_ptr advanced $((after - before)) frames during a test tone"
else
  echo "hdspe-reset: still frozen (${before:-0} -> ${after:-0})" >&2
  echo "  the DMA did not come back: a full power cycle is the remaining fix" >&2
  exit 1
fi
