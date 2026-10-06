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
{
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    (pkgs.writers.writePython3Bin "questyle-ctl" { } (
      builtins.readFile ./questyle/questyle-ctl.py
    ))
  ];
}
