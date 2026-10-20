Shared pleamar scene libraries for the shell: `palette.plm` (theme tokens) and `capsule.plm` (the
widget background) are written; `menu.plm` and `icons.plm` are the next two, their surfaces frozen
in `files/pleamar/docs/INTERFACES.md`. Each library is strict and checked through a small consumer
scene (`--check` refuses to open a library file on its own). Scenes under `shells/` import them
explicitly, palette first; keep scene-specific behaviour out of this directory — a change here lands
in every scene at once, so APIs stay small, stable and documented in
`files/pleamar/docs/INTERFACES.md`.

`plugins/` holds the plugins: a library with its logic next to it (`<name>.plm` + `<name>.luau`),
whose state lives in a process of its own. `plugins/spectrum/` is the reference (the CAVA analyser);
every plugin ships a `<name>.check.plm` consumer so the gate compiles it. The boundary rules, the
compiler traps and the port order are `INTERFACES.md` §10.
