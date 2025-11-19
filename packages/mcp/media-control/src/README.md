# media-mcp

Lightweight MCP server that exposes local media controls:

- Reads playback information from MPD (artist, track, progress, queue size).
- Offers playback controls (`play`, `pause`, `next`, etc.).
- Queues tracks by artist without leaving chat clients.
- Controls PipeWire volume via `wpctl` (set, delta, mute/toggle).

The server accesses MPD using the configured host/port (defaults to `localhost:6600`) and uses
PipeWire's default sink (`@DEFAULT_AUDIO_SINK@`) for volume commands. Override these via CLI flags
or the following environment variables:

- `MCP_MPD_HOST` / `MCP_MPD_PORT`
- `PIPEWIRE_SINK`
- `WPCTL_BIN`

This repository wires the binary into Home Manager so dev tools automatically pick it up alongside
the other MCP servers.
