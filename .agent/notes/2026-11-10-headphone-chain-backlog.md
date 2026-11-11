# The headphone chain: what is left after the 2026-11-10 split

The split itself is committed as `e1168f2`
(`[hardware/audio] Split the DSP per output and make the inserts lazy`): a second CamillaDSP
instance on port 1235, its own `headphones` sink, a router that wires it to the USB DAC, and lazy
lifetime for both inserts. This note is the backlog: what has to happen before the chain is usable,
and what is still a guess.

## 0. It is switched, and the sink is there

Done 2026-11-10: the switch ran, and `systemctl --user restart pipewire wireplumber` was needed
afterwards — a switch alone does not create `headphones`, because the loopback is a
`pipewire.conf.d` module the running daemon reads only at startup. `pwout status` now reads:

```
default output: game-stereo
monitors:       game-stereo  (CamillaDSP running, present)
headphones:     headphones  (CamillaDSP stopped, present; DAC match none)
```

`camilladsp-headphones` is stopped (no DAC yet), `pwout headphones` refuses, and the speaker daemon
is started by its router rather than at login.

## 1. The E1DA match string is a guess

`hardware.audio.dsp.headphones.dacMatch` is a case-insensitive regex over a sink's node name and
description, and it defaults to `E1DA` because the DAC was not plugged in while this was built.
`pwout dac` prints every sink and the ones that match.

If the real node does not contain `E1DA` (the USB product string decides), set the option to a
substring that does. Acceptance: with the DAC plugged and `pwout headphones` selected, the router
logs `dsp: headphones -> camilladsp-headphones -> <dac>`; unplugging the DAC returns the default to
`game-stereo` and the log says so.

## 2. Done in aurora: the pane and the CLI point at 1235

Fixed in the aurora repo, commit `808f9fd`
(`[camilla] The headphone EQ belongs to the headphone chain, and the frame names it`): the core
`:headphones` pane and the `headphones` CLI address the headphone instance
(`camilla::chain::DAEMON`, port 1235), and an apply writes the model into
`~/.config/camilladsp/headphones.yml` after the daemon validates it — the title carries the model's
name (`EQ: Sennheiser — HD 600`), restore removes it, and the pane's chip and the player's status
bar read the file without a socket, so the answer survives the lazy chain being stopped.

The `[[plugin]] name = "camilla"` tab stays on 1234 on purpose: it is the speaker DSP surface. The
known hazard is closed from the other side — the tab now refuses a config whose `capture.node_name`
is not the active instance's (`belongs_to_chain`), so page 3 cannot hand `headphones.yml` to the
speaker daemon.

What is left is the build: the player package builds from the `aurora-src` flake input, so the fix
reaches `/run/current-system` only after a lock bump (`just update`) and a switch — or `nix build`
of the package for a try.

## 3. The switch has a key in the player

`alt+o` and `:audio speakers|headphones|status` in aurora (`808f9fd`) run `pwout` and print its
answer on the status line, so the frame can choose the output; the refusal for an absent DAC is the
script's own sentence. A Hyprland chord next to the `pwroute` ones is still nobody's, and a bar chip
on the desktop side would be the third face of the same choice.

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
  Then `pwout speakers` and confirm the monitors' sound is identical to before the model. (The
  player's half was verified against a stand-in instance on 1237 — apply, file, restart from the
  file, restore, and the speaker instance untouched — see `docs/plugin-camilla.md`, but no E1DA was
  plugged in.)
- Lazy lifetime: with headphones selected, `camilladsp` must leave `pw-top` after the idle grace;
  switching back must put it in the path before the next track starts.
- The `node.autoconnect=false` pin on `playback.game-stereo`: if a game or MPD comes back unlinked
  after a WirePlumber restart, the direct path is the thing to check first
  (`pw-link -l | rg game-stereo`).
