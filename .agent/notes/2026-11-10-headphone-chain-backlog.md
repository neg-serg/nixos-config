# The headphone chain: what is left after the 2026-11-10 split

The split itself is committed as `e1168f2`
(`[hardware/audio] Split the DSP per output and make the inserts lazy`): a second CamillaDSP
instance on port 1235, its own `headphones` sink, a router that wires it to the USB DAC, and lazy
lifetime for both inserts. This note is the backlog: what has to happen before the chain is usable,
and what is still a guess.

## 0. It is not switched yet

The commit is only in the checkout. The switch needs the owner's password:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#trantor --option substitute false
systemctl --user restart pipewire wireplumber   # a switch does not reread pipewire.conf.d
pwout status
```

A switch alone does not create `headphones`: the loopback is a `pipewire.conf.d` module, and the
running daemon reads that directory at startup. Until the user manager's PipeWire restarts (or a new
login), `pwout headphones` has nothing to select.

Acceptance: `pwout status` lists both sinks; `camilladsp-headphones` is **stopped** (no DAC yet);
`pwout headphones` refuses; and `systemctl --user is-active camilladsp` is `active` while
`game-stereo` is the default — the daemon is no longer a login unit, the speaker router starts it.

## 1. The E1DA match string is a guess

`hardware.audio.dsp.headphones.dacMatch` is a case-insensitive regex over a sink's node name and
description, and it defaults to `E1DA` because the DAC was not plugged in while this was built.
`pwout dac` prints every sink and the ones that match.

If the real node does not contain `E1DA` (the USB product string decides), set the option to a
substring that does. Acceptance: with the DAC plugged and `pwout headphones` selected, the router
logs `dsp: headphones -> camilladsp-headphones -> <dac>`; unplugging the DAC returns the default to
`game-stereo` and the log says so.

## 2. aurora still points at the speaker instance

`~/.config/aurora/skins.toml`, the `[[plugin]] name = "camilla"` block, has no `url` key, so the
pane talks to `127.0.0.1:1234` — the speaker instance. A headphone model applied from page 5 still
lands on the monitors, i.e. the original complaint is only half fixed until this points at 1235:

```toml
[[plugin]]
name = "camilla"
enabled = true
url = "127.0.0.1:1235"
```

That is a user-state file, no rebuild needed. The `headphones` CLI has the same default: `apply`
targets 1234 unless `--daemon 127.0.0.1:1235` is passed. Changing the default lives in the aurora
repo, and the system package builds from the `aurora-src` flake input — that needs a commit there
plus a lock bump (`just update`), not a `/etc/nixos` edit.

Known hazard after the pane points at 1235: page 3 lists every config in `~/.config/camilladsp` and
applies the selected file with `SetConfigFilePath` + `Reload`. Applying `default.yml` (the speaker
config) to the headphone instance would create `camilladsp-capture/-playback` next to the speaker
instance's nodes and the router would fall back to the direct path. Recovery is a restart of
`camilladsp-headphones` (its ExecStart names `headphones.yml`). A filter by instance would close it.

## 3. The switch has no key

`pwout` is the only way to choose the output. A Hyprland chord next to the `pwroute` ones, or a bar
chip, would make it usable without a terminal; the bar already reads levels from `game-stereo`.

`pwout headphones` refuses while the DAC is absent on purpose — selecting it would just be a silent
output.

## 4. The chosen semantics, written down

- "In use" means: the sink is the default output, **or** a client stream is linked into it. MPD
  keeps its stream while paused (measured), so the DSP stays up through a pause and goes down only
  when MPD closes the output (stop) or the output is switched.
- The selected output's DSP is running before playback starts, so the first track is not peeled off
  the insert. Switching outputs mid-track hands the audio over in tens of milliseconds (the DSP
  links are added first, then the direct link is dropped).
- Race, accepted: `set-default.sh` reads `default.configured.audio.sink` a moment after WirePlumber
  starts. If WirePlumber restores its saved default later, the restore wins — the result is right,
  but a login can log the speaker default being set once. If the headphone choice is ever lost, the
  fix is a state file written by `pwout` and applied by a unit ordered after `wireplumber`.

## 5. Not yet verified against the hardware

- End to end with the real E1DA: the model audible on the headphones only, the monitors unchanged.
  Then `pwout speakers` and confirm the monitors' sound is identical to before the model.
- Lazy lifetime: with headphones selected, `camilladsp` must leave `pw-top` after the idle grace;
  switching back must put it in the path before the next track starts.
- The `node.autoconnect=false` pin on `playback.game-stereo`: if a game or MPD comes back unlinked
  after a WirePlumber restart, the direct path is the thing to check first
  (`pw-link -l | rg game-stereo`).
