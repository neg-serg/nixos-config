# 2026-11-25 — the pleamar shell moved to its own flake

Status: extracted, published, wired and active. The gaps at the bottom are
deliberate and each names how to close it.

Repository: <https://github.com/neg-serg/pleamar-config> (public, branch `main`,
initial import `8e13f80`). Live checkout: `/home/neg/src/pleamar-config`.

## What moved out of this tree

| was here | now |
| --- | --- |
| `files/pleamar/{shells,lib,themes,scripts,docs,art.plm,theme.plm}` | repository root of `pleamar-config` |
| `packages/pleamar-{calendar,harness,kbdlayout,picker,sysmon,theme,weather}` | `packages/` there |
| `packages/wallpaper-palettes` | `packages/wallpaper-palettes` there (theme pipeline) |
| `packages/overlays/pleamar-*.patch` (12) | `patches/`, applied by its overlay |
| `modules/user/nix-maid/gui/pleamar.nix` | `modules/shell.nix` |
| `modules/user/session/greetd.nix`, `greetd/{login-layer,session-wrapper}.sh` | `modules/login.nix`, `modules/` |
| `scripts/dev/{check-plm,check-plm-theme,check-pleamar-geometry,check-pleamar-health,check-plugin-render,check-scene-events,pleamar-login-cpu,screen-numbers,capture-window}.sh` | `dev/` |
| pleamar Justfile targets (`pleamar-check`, `health`, `pleamar-geometry`, `pleamar-restart`, `pleamar-cpu`, `screen-numbers`, `plm-theme`, `scene-events`, `render-plugins`, `rig`) | `Justfile` there |

The `pleamar`/`pleamar-wm` flake inputs, the `pkgs.pleamar`/`pkgs.pleamar-wm`
overrides and the `pkgs.neg.pleamar-*` attributes are gone from this repo.

## How the host consumes it

- `flake.nix`: `pleamar-config.url = "path:/home/neg/src/pleamar-config"`,
  `inputs.nixpkgs.follows = "nixpkgs"`.
- `flake/lib.nix`: `inputs.pleamar-config.overlays.default` supplies
  `pkgs.pleamar`, `pkgs.pleamar-wm`, the seven workers + `wallpaper-palettes`
  and `pkgs.pleamar-tree` (the scene tree in its import layout).
- `flake/nixos.nix`: imports `inputs.pleamar-config.nixosModules.default`
  (`modules/shell.nix` + `modules/login.nix`).
- `modules/user/nix-maid/gui/pleamar-config.nix` is the only host glue: it sets
  `pleamar-config.enable` from `config.lib.neg.pleamarEnabled` and
  `pleamar-config.liveRoot` to the checkout.
- `just pleamar-sync` refreshes the `path:` input; `just deploy` runs it first.

## Verification done that day

- `just fmt`, `just lint` (18/18), `just check` — green.
- Toplevel built and activated with `just agent-switch`; `/run/current-system`
  matches the built store path.
- `pleamar-bar.service` active, `pleamar --say bar describe` answers.
- `~/.config/pleamar/shells/bar` → `/home/neg/src/pleamar-config/shells/bar`
  (live), `/etc/pleamar-lock` → `pkgs.pleamar-tree`.
- In `pleamar-config`: `just check` compiles 22 scenes; `pleamar` (patched
  engine), the crates and the tree build.

## Gaps to fix later

1. **The login screen is not live.** `modules/login-layer.sh` still probes
   `/etc/nixos/files/pleamar/shells/lock/lock.plm`; that path is gone, so the
   login phase always runs the store copy from `/etc/pleamar-lock`.
   Fix: substitute `@liveRoot@` from `pleamar-config.liveRoot` in
   `modules/login.nix`, probe `${liveRoot}/shells/lock/lock.plm`, keep the store
   tree when `liveRoot` is null. Verify by editing that scene, re-locking
   (`just pleamar-sync`), restarting greetd and seeing the edit at login.
2. **`path:` inputs are narHash-locked.** Any write or git operation in the
   checkout changes the hash; `nix build`/`nix flake check` then refuse with
   "NAR hash mismatch" until `just pleamar-sync`. That is why `deploy` runs it.
   If the churn gets annoying, switch the input to
   `github:neg-serg/pleamar-config` and keep `liveRoot` for the live links:
   rebuilds then follow pushed commits with no sync step.
3. **The public flake still assumes this host.** `modules/shell.nix` and
   `modules/login.nix` read `config.lib.neg.{systemdUser,homeDir}`,
   `neg.mkDirLinks`/`neg.mkHomeFiles`, `users.users.neg.maid` and
   `features.gui.wallpaperPicker.enable`. To make it standalone, add options
   (user name, systemd-user helper, picker flag) and drop the host lib.
4. **Historical docs keep host paths.** Inside `pleamar-config` the
   `files/pleamar/` prefix was rewritten, but `docs/PARITY.md` and `AGENTS.md`
   still cite `/etc/nixos/.agent/plans/...` and `files/quickshell` on purpose
   (the port's reference and history).
5. **The dev scripts are copies.** `dev/check-plm.sh` lost the host's `pmap`
   fan-out (plain loop now), and this repo's `scripts/dev/lib.sh` no longer has
   `resolve_pleamar_tool`.

## Commits

- `9dbfaf28e` — the extraction (files, packages, modules, patches, docs).
- `b9ed1b80c` — `just pleamar-sync` + the narHash note in `AGENTS.md`.
- `ec2aa2c9e` — drop the orphaned `resolve_pleamar_tool`.
- `pleamar-config` `8e13f80` — initial import.
