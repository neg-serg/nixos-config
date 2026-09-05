# neg — a fork of the LiangShen preset (anchored-standard)

A personal fork of the **LiangShen mode** preset (a two-phase anchored-standard agent) for DeepSeek
Harness, maintained declaratively in this repository instead of the third-party plugin
`@linxin666/dsh-liangshen` (whose patch row was unmounted — the preflight stopped resolving the
package). The preset identifier is **`neg`** (renamed from `liangshen-fork` at the user's request):
the picker, sessions and the default reference `neg`.

## What the preset does

1. **Phase 1** — the model's first request sees only the Minimal surface: a persistent `bash` +
   `str_replace_editor`, one persona line, no runtime contexts, workspace instructions or skills
   catalog. The goal is to "anchor" the model's execution trajectory (in the community eval Minimal
   scores above Standard/PTC, see [xiaobright/modeltest](https://github.com/xiaobright/modeltest)).
1. **Promotion** — after the first saved `tool/call`, it waits for a "minimal-like" first reasoning
   block (contains `we`, without `let me`), with a fallback after 4 steps; an answer without calls
   promotes immediately.
1. **Phase 2** — the wire switches to Code Mode (PTC): a single `run_code` over the full tool
   registry, all prompt sections return, a working-directory line is added to the persona, and the
   workspace instructions and skills catalog arrive with a one-step delay.

## How it is arranged

- Preset files: `modules/user/nix-maid/apps/dsh-liangshen-fork/` (`preset.yml` — name/description/
  order in the picker, `agent.cordis.yml` — composition, `tool-bootstrap.mjs` — two-phase
  bootstrap, `NOTICE` — origin and licenses). The behavior is identical to upstream; it is edited
  here.
- The `modules/user/nix-maid/apps/dsh-liangshen-fork.nix` module syncs the files into
  `~/.dsh/.agent-presets/neg/` (the roster's discovery root; the preset id — `neg`) on every
  rebuild and login. The sync is always forced — local edits in `~/.dsh/.agent-presets/` are
  overwritten; the repository is the source of truth. The directory is excluded from the module
  auto-import in `apps/default.nix`.
- The default preset: `agent-presets.default: neg` in `~/.dsh/settings.yaml` (read with
  hot-reload, applies to **new** sessions; no dsh restart is needed). A duplicate fallback in the
  roster config (`- id: agent-presets / config.default` in
  `~/.dsh/profiles/web/cordis.patch.yml`, see `dsh-market.nix`) guards against a settings.yaml
  reset.
- The built-in `standard` preset is removed from the dsh package build
  (`packages/dsh/default.nix` — postInstall cuts out `config/agent-presets/standard`), so it is
  absent from the picker.
- The original upstream `liangshen` preset (from the unmounted
  `@linxin666/dsh-liangshen` plugin) is removed declaratively by the fork's ensure-script; the
  plugin leftover was cleaned from `~/.dsh/profiles/node_modules`.

## Changing the behavior

Edit `modules/user/nix-maid/apps/dsh-liangshen-fork/agent.cordis.yml`, then
`sudo nixos-rebuild switch --flake .#odin --option substitute false` (or wait for the login) — the
activation script re-syncs the preset. The picker default is changed via the GUI (roster → "Set as
default") or by editing `settings.yaml`.

## Removal

Remove the module and the directory, restore the exclusion in `apps/default.nix`, delete
`~/.dsh/.agent-presets/neg/` and the `agent-presets.default` key from `settings.yaml`.
