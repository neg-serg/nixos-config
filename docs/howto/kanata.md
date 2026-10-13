# Kanata: CapsLock layout — status and history

> Status: **simple `CapsLock → Ctrl` scheme (active, stable)**. Caps navigation (arrows on
> `caps+hjkl` and Ctrl-combo aliases) is **reverted and temporarily banned from deployment** — see
> “Decision” below.

## Current state (2026-08-20)

- The deployed config is **simple**: `caps` → `lctl` (see `files/cli/kanata/kanata.kbd`; deployed
  via `modules/user/nix-maid/sys/kanata.nix` → `~/.config/kanata/kanata.kbd`).
- Process: `kanata --cfg ~/.config/kanata/kanata.kbd` (systemd user service, see
  `modules/hardware/input/default.nix`). Feature flag: `features.input.kanata.enable`.
- The applied generation switch includes this revert (commit `6419062a`).

## caps-nav history (what was tried and why it was reverted)

A series of experiments with CapsLock navigation (arrows `caps+hjkl`, `caps+space` = Tab, `caps+q` =
Esc, `caps+w` = F24, later aliases `caps+backspace` = Ctrl+H, `caps+delete` = Ctrl+K, `caps+enter` =
Ctrl+J):

| Commit                 | What it did                                                                                           |
| ---------------------- | ----------------------------------------------------------------------------------------------------- |
| `ad873820`, `487f8a8a` | CapsLock = Ctrl **and** an instant navigation layer (caps+hjkl → arrows)                              |
| `a237ca77`             | Time-split: quick `caps+key` = Ctrl+key, hold >200 ms = navigation                                    |
| `499517b7`             | “Instant caps-nav”: reverted time-split (no reliable arrows), instant navigation + Ctrl-combo aliases |

**Bottom line:** the latest version (`499517b7`) is **confirmed broken** — applying it broke input
(incorrect arrows/modifiers, mangled Ctrl combos). Therefore:

## Decision (user, 2026-08-20)

1. Caps navigation is **reverted** (commit `6419062a`, plain `caps → Ctrl`) and is **not applied**
   for now.
1. We will return to it as a **separate experiment**, once the other tasks are done — not “woven
   into” regular work, and not applied in a hurry.
1. Any work with kanata must be done **carefully**: verify that the deployed scheme is exactly the
   simple one and test after the switch (`head ~/.config/kanata/kanata.kbd`, live typing) before
   closing the task.

## Verification after the switch

```bash
head ~/.config/kanata/kanata.kbd      # should show: (defsrc caps) / (deflayer base lctl)
pgrep -af 'kanata --cfg'               # process is alive
systemctl --user is-active kanata.service
```

If caps-nav commits appear in the tree again, cross-check against this document before building: by
default they **must not** end up in the deploy until a separate experiment has been agreed on.

## Input chain: virtual devices and the neru coupling (2026-10-13)

The live path is `physical keyboard → kanata → neru (evdev proxy) → Hyprland`; the compositor sees
neru's proxy as the "main" keyboard.

Incident: kanata crash-looped five times in four seconds (`failed read: Device or resource busy`)
because it also tried to grab keyboards that other daemons write (`ydotoold virtual device`,
`vicinae-snippet-virtual-keyboard`). Every restart forced neru to re-take the physical keyboards
(`a remapper released it` / `Yielding physical keyboards … to a remapper that just started`), and
the long-lived neru proxy drifted out of sync: `W` stopped reaching any application until neru was
restarted.

Rules that follow from it:

- `linux-dev-names-exclude` in `files/cli/kanata/kanata.kbd` lists every virtual keyboard
  (`neru-keyboard-proxy`, `ydotoold virtual device`, `vicinae-snippet-virtual-keyboard`); names are
  matched exactly — kanata has no glob support. The remapper touches physical keyboards only.
- `modules/hardware/input/default.nix` sets `StartLimitIntervalSec = 0`, so a crash loop cannot kill
  the remapper permanently (the systemd default is 5 starts / 10 s).
- `modules/user/session/neru.nix` sets `partOf = [ "kanata.service" ]`: every kanata restart also
  restarts neru, so a stale proxy cannot survive a remapper restart.

Recovery if a single key stops registering:

```bash
systemctl --user restart neru      # stale neru proxy — returns the key instantly
systemctl --user restart kanata    # now also restarts neru
```
