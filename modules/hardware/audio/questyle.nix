# Questyle QCC Dongle Pro2 - USB-C Bluetooth audio transmitter (USB 0a12:4007).
#
# The dongle is a BT *host* of its own: PipeWire only sees a USB sound card and
# whatever it streams goes out to the paired headset. Codec/pairing/Auracast
# settings live inside the dongle and are driven by its own buttons plus a
# proprietary HID channel (usage page 0xFF00, 62-byte output reports) that the
# vendor app speaks; there is no public protocol description.
#
# questyle-ctl keeps that channel reachable from Linux: `info` (state of USB /
# ALSA / PipeWire), `watch` (record the reports the dongle sends - read-only,
# used to decode the protocol), `raw`/`feature` (manual frames).
#
# writers.writePython3Bin runs flake8 over the script, and flake8's stock rules
# disagree with the formatter this repo uses (black at 79 columns): black writes
# slices as `b[4 : 4 + size]` (E203: whitespace before ':'), and a docstring line
# that cannot be split stays 80 characters (E501). Both are silenced here rather
# than by uglifying the script; ruff+black (scripts/dev lint) already gate the
# source itself.
{
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    (pkgs.writers.writePython3Bin "questyle-ctl" {
      flakeIgnore = [
        "E203" # black's slice spacing (b[4 : 4 + size])
        "E501" # line length: unsplittable docstring lines
        "W503" # line break before a binary operator (black)
      ];
    } (builtins.readFile ./questyle/questyle-ctl.py)) # USB/ALSA/PipeWire + HID channel of the dongle
  ];
}
