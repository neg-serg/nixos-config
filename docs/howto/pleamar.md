# pleamar shell (features.gui.pleamar)

Alternate desktop shell: [pleamar](https://github.com/k4ditano/pleamar) is a Rust Wayland runtime
with a declarative `.plm` scene language. The port replaces the Quickshell shell area by area — bar,
panels, notifications, toast, launcher — and every scene is an independent process with its own unit,
so one can restart or be measured without touching the others.

**Off by default.** `features.gui.pleamar` is `false` (`hosts/trantor/default.nix`): the shell was
disabled after its dual-run trial against Quickshell. Scenes and `pkgs.pleamar` stay in the tree —
flip the flag to retry.

## Sources of truth

| what | where |
| --- | --- |
| scene layout, running one scene by hand, measurement | `files/pleamar/README.md` |
| frozen scene/IPC catalog, palette and capsule APIs, label policy | `files/pleamar/docs/INTERFACES.md` |
| phases, gates, budgets, open work | `.agent/plans/2026-10-16-pleamar-superplan.xml` |
| module wiring, units, guards | `modules/user/nix-maid/gui/pleamar.nix` |

The `.plm` files live in `files/pleamar/shells/<scene>/<scene>.plm`; directory name, scene name and
IPC name are the same string.

## Units and guards (when the flag is on)

- `pleamar-<scene>.service` for every scene in `pleamarScenes` (`bar`, `panels`, `notifications`,
  `toast`, `launcher`), each running
  `pleamar --scene ~/.config/pleamar/shells/<scene>/<scene>.plm --no-hud` with memory/CPU caps.
  `lock`, `overlay`, `overview` and `proof` exist under `files/pleamar/shells/` but are not started
  by the module — `lock` is not in the scene list at all, `overview` is a deliberate omission (a
  resident process for one IPC verb costs more than the bind).
- `pleamar-health` + `pleamar-health.timer` — hang watchdog: probes the bar scene (2-minute period,
  first run after 5 minutes) and restarts the scene when it stops answering.
- `pleamar-theme` — runs the theme pipeline (`files/pleamar/scripts/theme`) on every wallpaper
  change, writing `~/.config/pleamar/theme.plm`.
- `pleamar-cleanup-symlink` — removes stale deployed links; without it a scene dies on a missing
  `.plm` between cleanup and activation.
- Login-phase guard: while `%t/quickshell-login/login-phase` exists the greeter owns the screen and
  no session scene may start; systemd re-evaluates the condition once the marker is gone.

## Enable / disable

```console
# enable
$EDITOR hosts/trantor/default.nix     # features.gui.pleamar.enable = true;
$ nixos-rebuild switch --flake .#trantor --option substitute false
# then log out and back in: the scenes are session units, not a live restart
```

Quickshell stays the default shell until the flag is flipped; the two are not meant to run together.

## Gate

`scripts/dev/check-plm.sh` validates every scene and runs as part of `just lint`, so a broken `.plm`
fails before a switch rather than at login.

## Open state (2026-10-17)

Notifications still miss their budget (1.0 % of a core against the 0.5 % target), `tests/evidence/`
is missing so the G3/SC2 gates are unproven, the lock scene is not wired into `pleamarScenes`, and
the plugin phase (PH3-P) has not started. The superplan carries the per-phase status.
