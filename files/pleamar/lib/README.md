Shared pleamar scene libraries for the shell: `palette.plm` (theme tokens) and `capsule.plm` (the
widget background) are written; `menu.plm` and `icons.plm` are the next two, their surfaces frozen
in `files/pleamar/docs/INTERFACES.md`. Each library is strict and checked through a small consumer
scene (`--check` refuses to open a library file on its own). Scenes under `shells/` import them
explicitly, palette first; keep scene-specific behaviour out of this directory — a change here lands
in every scene at once, so APIs stay small, stable and documented in
`files/pleamar/docs/INTERFACES.md`.
