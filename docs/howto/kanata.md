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
