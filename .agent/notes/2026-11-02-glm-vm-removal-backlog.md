# GLM: the VM-era pieces that can be deleted

GLM control has moved to the host port: `glm5d` owns the GLM adapter and `glm5ctl` sets volume/mute
through it (`packages/genlc-rs`). The dockur Windows VM, GLM's Windows app and the MIDI/OSC bridges
are the fallback now — stopped, not started by default, and deletable as a whole.

Status on 2026-11-02: the `windows` container is stopped (`restart=no`), its image and the 14G
`/storage` volume are kept; `glm5d` leases all three monitors; the bar's Genelec tile and the
keyboard volume keys drive it.

## Before deleting

- `glm5d` has run a while without lease failures and its volume/mute were checked by ear. The mute
  is confirmed on hardware now (2026-11-02): the adapter frame `01 2B 01/00` alone did nothing, the
  monitors act on the per-session `2B 03` (mute) / `2B 04` (unmute) rounds that GLM sends after it,
  and `glm5d` now sends them to every leased session.
- The plugin is on the daemon path (`Genelec.daemon=true`) and the keyboard volume keys reach it
  (`XF86Audio*` binds in `files/gui/hypr/hyprland.lua`).
- Nothing uses the OSC API (`127.0.0.1:9000`) or the four virtual MIDI slots.
- No capture session is running (`docs/runbook-genelec-glm.md`).

## The VM itself

- container `windows` (image `dockurr/windows`), volume `/storage` (~14G sparse,
  `~/.local/share/containers/storage/volumes/f1047db9.../_data`)
- `hosts/trantor/services/windows-vm.nix`
- `packages/dockur-windows/` (Dockerfile, `oem/` with the GLM MIDI bridge)
- `docs/howto/windows-vm-dockur.md`

Deleting: `podman rm windows`, `podman volume rm <volume>`,
`podman rmi docker.io/dockurr/windows:latest`, then the files above.

## Units that only serve the VM

In `modules/user/nix-maid/sys/user-services/`:

- `glm-monitoring.nix`: `glm-osc` (UDP :9000), `glm-midi-relay` (TCP :9003/:9004),
  `glm-adapter-auto` (+ timer), `ensure-vm-proxy-alias` (+ timer)
- `media-proxy.nix`: `rtpmidid` (RTP-MIDI)

## Packages, scripts, files

- `packages/glm-osc/`, `packages/rtpmidid/`, `files/rtpmidid/config.ini`
- `packages/local-bin/bin/glm-midi` (CC packets over the relay),
  `packages/local-bin/scripts/glm-sync` (reads the VM GLM window),
  `packages/local-bin/scripts/glm-adapter` and `glm-vm-netfix` (adapter placement and VM netns),
  `modules/media/audio/core-packages/glm-adapter-priv.sh`
- `packages/local-bin-tools/src/glm_midi_relay.rs` (the Rust relay)
- `packages/local-bin/scripts/genlc-media` (the old keyboard-wheel path; the Hyprland binds call the
  plugin directly now)

## The plugin's MIDI branch

`files/pleamar/lib/plugins/genelec/genelec.luau`: `commitMidi`, the `fact.midi` arms of
`commit`/`toggle`, and the `midi := not onHost` branch of `probeLegacy`. The daemon and the host
`genlc` path stay. Removing it also drops `glm-midi` and the relay from the plugin's `permissions`.

## What stays

- `glm5d`/`glm5ctl` (`packages/genlc-rs`), `genlc` (discover/set-volume), `glm-vol` (the level file
  the plugin reads back)
- `glm-usbmon-priv` and `docs/runbook-genelec-glm.md` (still the capture tooling for the protocol
  work)
- `virtual-midi` (SuperCollider routing, not the VM)
