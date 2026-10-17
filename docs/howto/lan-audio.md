# LAN audio access (MPD + PipeWire)

Expose the audio stack to the local network via `features.media.audio.lanAccess.enable`:

- **MPD** — `bind_to_address` becomes `any`, so MPD (port 6600) is reachable from LAN clients
  (`mpc -h trantor`, mobile MPD apps, etc.). No password — anyone on the LAN can control playback.
  Firewall port 6600 was already open.
- **PipeWire, receive** — Pulse-compatible TCP server on port 4713
  (`pipewire-pulse.conf.d/20-network.conf`). Other devices can play audio through this machine, e.g.
  `PULSE_SERVER=192.168.0.10:4713` on a Linux client, or any PulseAudio-over-network client.
- **PipeWire, send** — an RTP multicast sink (`libpipewire-module-rtp-sink`, node name `rtp-sink`)
  that broadcasts anything routed to it to `224.0.0.56:46000` over the interface set in
  `features.media.audio.lanAccess.rtp.interface` (default `net1`). Receive it with e.g. VLC:
  `rtp://224.0.0.56:46000`.

Example (host):

```nix
{
  features.media.audio.lanAccess.enable = true;

  # RTP multicast interface (only if not net1)
  features.media.audio.lanAccess.rtp.interface = "net1";
}
```

Usage notes:

- To broadcast a specific app to the LAN: `pw-link <app-output> rtp-sink` or set `rtp-sink` as the
  default sink (`wpctl status` to find its id).
- Multicast loop is enabled (`net.loop`), so the stream can be tested on this machine too with VLC:
  `rtp://224.0.0.56:46000`.
- RTP is outgoing UDP multicast — no firewall rule required; the 4713 TCP rule is added
  automatically when the flag is enabled.
- Both services are unauthenticated — only enable on a trusted LAN.
