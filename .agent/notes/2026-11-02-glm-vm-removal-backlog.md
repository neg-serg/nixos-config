# GLM: the VM-era pieces that were deleted

Executed 2026-11-03. GLM control is host-only now: one binary `genlc` (subcommands `daemon`,
`status`, `volume`, `mute`) and one user unit `genlc.service`. The dockur Windows VM, GLM's Windows
app, the MIDI/OSC bridges and rtpmidid are gone; the runtime podman container, image and 14G volume
had already been removed when the tree was cleaned, so nothing was left on disk.

## Removed

- the VM: `hosts/trantor/services/windows-vm.nix`, `packages/dockur-windows/`, the dockur howto, the
  `.11` host alias, the VM firewall ports (10811/10812/9003/5010/5011) and the RDP telegram timer
- the bridges: `glm-osc` (UDP :9000), `glm-midi-relay` (TCP :9003/:9004), `rtpmidid`, `glm-midi`,
  `glm-adapter`/`glm-vm-netfix`, `glm-sync`, the plugin's MIDI branch
- the daemon split: `glm5d`/`glm5ctl`, `glm-vol`, `genlc-media`, `genlc-diagnose` — folded into
  `genlc`
- the passthrough: `vfio-pci.ids` for the iGPU, vfio udev rules, the `glm-adapter-priv` helper and
  its NOPASSWD entry

## What stays

- `genlc` (`packages/genlc-rs`) and `genlc.service`, the only owner of the USB adapter
- the mute rounds: the adapter frame `01 2B 01/00` alone does nothing; the monitors act on the
  per-session `2B 03` (mute) / `2B 04` (unmute) rounds, which the daemon sends to every lease
- `glm-usbmon-priv` and `docs/runbook-genelec-glm.md` for protocol captures
- `virtual-midi` (SuperCollider routing, not the VM)
