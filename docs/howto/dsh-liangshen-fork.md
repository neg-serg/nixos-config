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
  order, `agent.cordis.yml` — composition, `tool-bootstrap.mjs` — two-phase bootstrap, `NOTICE` —
  origin and licenses). The behavior is identical to upstream; it is edited here. The sibling
  `dsh-fast/` directory is the same shape for the `fast` preset.
- **Declarations, not directories** (dsh ≥ 0.1.7 / 0.2.0): the harness composes a preset from a
  declaration row (`@deepseek-ai/dsh-agent-preset`) carried by a patch layer, and the old
  `~/.dsh/.agent-presets/<id>/` discovery root is dead — nothing reads it. The deployment declares
  both presets itself, because the tui profile mounts neither the web-app bundle (which carries the
  shipped `standard`/`ptc`/`minimal`/`cordis`) nor any other preset source:
  - `dsh-presets.nix` holds the data (`id`, `name`, `order`, `description`, the `plugins` file, the
    sidecar files) and the JSON handed to the writer;
  - `dsh-tui-preset-patch.py` writes the owned blocks of the profile's `cordis.patch.yml` on every
    rebuild and login: the two `- insert: [{id: preset-<id>, …}]` declarations, the registry default
    (`dsh-tui-agent-preset-registry.config.default`), and the plugin rows;
  - `dsh-tui-ensure.sh` copies each declaration's sidecars next to the patch file, because relative
    names inside a patch anchor to the file that carries it (`./tool-bootstrap.mjs` → the profile
    directory). A store path's file name carries its hash, so the JSON gives the destination name.
  - The retired `~/.dsh/.agent-presets/` root is removed once by the same caretaker.
- The `standard` preset is **not** removed from the package any more: it ships inside the
  `@deepseek-ai/dsh-web-app` bundle, which the terminal profile does not mount, so the picker there
  shows exactly the declared presets. The web profile does mount that bundle; hiding `standard`
  there is a profile-layer patch (`- id: preset-standard` + `disabled: true`) rather than a package
  edit.
- The default for new sessions is the registry row's `config.default` (`neg`, written by the
  caretaker). `~/.dsh/settings.yaml` used to hold `agent-presets.default` — that is the retired
  0.1.x namespace and is ignored by 0.2.0; the live override is the registry's settings-backed
  `selectedDefault`, set from the picker ("Set as default") or the settings UI.

## Changing the behavior

Edit `modules/user/nix-maid/apps/dsh-liangshen-fork/agent.cordis.yml` (or `dsh-fast/`), then
`sudo nixos-rebuild switch --flake .#trantor --option substitute false` — or just log in: the
caretaker regenerates the profile patch layer. Plugin names must still exist in the installed
harness (`cordis-composition-reference`); 0.2.0-rc.2 renamed `@deepseek-ai/dsh-workflow-worker-thread`
to `@deepseek-ai/dsh-workflow-ptc`, which that file already carries.

## Removal

Delete the preset's entry from `modules/user/nix-maid/apps/dsh-presets.nix` (or the whole file plus
the `presets` import in `dsh-tui.nix` and the exclusion in `apps/default.nix`), then drop the
`dsh-<id>/` directory. The caretaker writes a layer without that declaration on the next rebuild or
login; nothing lives in `~/.dsh` to clean up.
