# dsh-status-rotator — a live status instead of "Deep diving..."

The `dsh-status-rotator` plugin (github:01Virex/dsh-status-rotator) replaces the hardcoded string
**"Deep diving..."** — the status of a running agent in the dsh web UI (the `TurnStatus` component
in `dsh-client-ui-conversation`) — with a rotation of phase-aware phrases, a typewriter effect and a
shimmering gradient.

## What it can do

- **Three phases**: `thinking` (0–15 s) → `running` (15–60 s) → `long` (after 60 s); a phase
  transition instantly changes the phrase set.
- **Typewriter** (`typeSpeedMs`, 0 = off) and **gradient shimmer** (CSS `linear-gradient` +
  `animation`, `speed` = seconds per cycle).
- The config is served by the node half at `/plugins/dsh-status-rotator/config.json` (the file is
  read from disk on every request) — edits apply on F5, no dsh restart is needed. The plugin does not
  touch the hour counter (which appears at the 15th second).

## Configuration

The files live in the plugin package inside the web profile:

- `~/.dsh/profiles/web/node_modules/dsh-status-rotator/config.json` — the working config (phrases,
  gradient, intervals);
- `config.example.json` — the fallback and the source for the seed step.

Keys: `intervalMs` (rotation, ms), `typeSpeedMs` (typewriter speed), `longAfterMs` (the
`long` phase threshold), `gradient.{enabled,colors,speed}`,
`phrases.{zh,en}.{thinking,running,long}`. The phrase language follows the dsh UI locale (on this
machine — `en`), so the Russian phrases live in the `en` group.

## How this is managed in NixOS

The plugin is part of the declarative list of the `dsh-market.nix` ensure-script (the module
`modules/user/nix-maid/apps/dsh-market.nix`):

- **Install** — `dsh plugin --profile web add github:01Virex/dsh-status-rotator`, if the package is
  missing from the profile's `package.json`. Around pnpm operations the
  `node_modules/@deepseek-ai` symlink (pointing at the read-only nix store) is "parked" aside: pnpm
  cannot write nested `node_modules` through it (EROFS/ENOENT), and any fresh install relinks the
  tree.
- **Seed** — `config.json` is copied from `config.example.json` if it is missing.
- **"neg look" patch** — a python step brings the config to the accepted shape, replacing **only
  stock values**: the rainbow gradient → a restrained omp palette (`#005faf`, `#367CB0`,
  `#6C7E96`, `#287373`, `#5E468C`, `#914E89`, speed 6), the English meme phrases → Russian.
  Manual edits to `config.json` survive rebuilds — the patch does not fire when the values are no
  longer stock.

That is, after any plugin reinstall (pnpm clean, `dsh plugin update`, market) the appearance is
restored automatically at the next login or rebuild.

## Nuances

- Config edits in `node_modules` survive a reload, but not a package reinstall (pnpm deletes the
  directory) — the module will bring the palette and phrases back.
- Want fully custom phrases/colors — edit `config.json`; the managed patch will not overwrite them
  (it reacts only to stock values).
- Reinstalling the plugin before the next rebuild rolls the look back to stock — the automation kicks
  in after `nh os switch`.
