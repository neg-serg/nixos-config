# Repository conventions (agents and coding)

Use the same expectations regardless of whether you work under `modules/` or
`modules/user/nix-maid/`; helpers live side-by-side so the patterns apply to both configurations.

## Key Locations

- Runtime helpers (`config.lib.neg.*`): defined in `flake/nixos.nix` specialArgs, exposed via
  `modules/core/neg.nix` (`mkHomeFiles`, `path`, `pathExists`, `enabled`, …).
- systemd-user helpers: `lib/systemd-user.nix` (`mkUnitFromPresets`, legacy `mkSimple*`).
- Feature definitions/options: `modules/features/`

## Package Availability Checks

- Before adding any `pkgs.*`/`nodePackages_*`, confirm the attribute exists using `nix search` (or
  any flake evaluation) against this repo. Only wire packages that exist in the currently pinned
  channel.

## QML / Quickshell Touches

- Stick to upstream Qt 6 best practices: small declarative components, property bindings over the
  imperative approach, no binding loops or global JS helpers, explicit signal handlers.
- Assume Qt 6+ APIs; review the latest Hyprland/Quickshell release notes before suggesting changes.
- QML syntax is checked by `scripts/dev/check-qml-syntax.sh` (invoked by `just lint`), which runs
  `qmlformat --dry-run` over `files/quickshell`; it validates syntax only, so style still relies on
  these conventions.

## Runtime Helpers (Preferred)

- Use `config.lib.neg.mkHomeFiles` or `neg.mkHomeFiles` instead of ad‑hoc `home.file` or shell
  commands.

## Activation Helpers

- Use per-file `force = true` instead of re‑adding global XDG cleanup.
- Local scripts: use `neg.mkHomeFiles` with `executable = true` (for example
  `{ ".local/bin/<name>" = { text = …; executable = true; }; }`) so the file is marked executable
  before linking.

## Systemd (User) Pattern

- Always combine `lib.mkMerge` with `config.lib.neg.systemdUser.mkUnitFromPresets` for consistent
  `After=/WantedBy=` wiring; avoid the legacy `mkSimple*` helpers (they have recursion edge cases).
- Examples:
  - Service: presets `["defaultWanted" "restartOnFailure"]` (+ `RestartSec` if not 10)
  - Graphical-session resident: presets `["graphicalSession" "restartOnFailure"]` (`graphicalWanted`
    when the unit must be pulled in but not stopped with the session)
  - Short-lived helper: preset `["oneshot"]`, add `wantedBy` only if something must pull it in
  - Timer: set `wantedBy = [ "timers.target" ]` directly.

## Editor Shim

- Use `v` (Smart Neovim shim at `~/.local/bin/v`) in bindings/scripts. It uses `nvr` to open files
  in an existing instance (and raises the window) or starts a new one if none exists.

## Soft Migrations / Warnings

- Emit guidance with `warnings = lib.optional cond "message";` instead of `builtins.trace`.
- Keep warning conditions cheap and avoid referencing `config.lib.neg` while evaluating options.

## Coding Style

- Formatting: run `nix fmt`/`just fmt` (treefmt) before committing. It runs `nixfmt` for Nix and
  `mdformat --wrap 100` for Markdown. Enable git hooks via `just hooks-enable` to auto-run
  formatters (`SKIP_NIX_FMT=1` to skip).
- Indent with 2 spaces; let nixfmt control wrapping/spacing. Avoid manual column alignment.
- Lists with complex elements expand one per line; attribute sets become multi-line once they hold
  more than one entry.
- Keep prose/strings around ~100 columns; move long comments above the expression they describe.
- Avoid `with pkgs;` around lists—refer to `pkgs.foo` explicitly. Using `with` inside local attrsets
  or helper scopes is fine.
- Always declare feature options centrally (see `modules/features/`) and gate module fragments via
  the relevant `features.*` flags.
- Structure modules with `lib.mkMerge [ … ]` and the helper sugar above. Factor package groups into
  local `groups = { … };` sets.
- Systemd user units/paths/sockets should reuse `config.lib.neg.systemdUser.mkUnitFromPresets`.
- For xdg-managed files prefer `home.file` with `force = true` where parent dirs are needed.
- Use `neg.mkHomeFiles` with `executable = true` for scripts under `~/.local/bin`.
- Keep warnings actionable via `warnings = lib.optional cond "…";` and ensure the condition is cheap
  (avoid referencing `config.lib.neg` while declaring the warning).
- Commit messages must follow `[scope] subject` unless performing `Merge`, `Revert`, `fixup!`,
  `squash!`, or `WIP`.

## Commit messages and the local hook

- Subject style: `[scope] short description` in English, ASCII only; e.g.
  `[quickshell/gui] improve keyboard indicator`. Scopes combine with `/` (`[cli/gui] …`) when a
  change touches several areas.
- Exceptions: Git-generated subjects like `Merge ...`, `Revert ...`, and `WIP:` are allowed.

Enable the repo hook locally:

```
git config core.hooksPath .githooks
```

The hook rejects commit messages that contain non‑ASCII characters or do not start with a bracketed
scope.

Additionally, a Markdown language policy is enforced:

- All docs live in English-only `*.md` files.
- `scripts/dev/check-markdown-language.sh` fails on any Cyrillic/CJK in `*.md` (only layout-glyph
  examples are allowlisted).

## Module Pattern & Option Helpers

- This repo favors a consistent module pattern and provides helpers in `lib/opts.nix`.
- Flag overview: `OPTIONS.md`; module recipes: `docs/howto/agent-recipes.md`. The generated
  docs-modules output no longer exists (removed in `0ceafa815`).

## Systemd user units

- Prefer `config.lib.neg.systemdUser.mkUserService` for module-shaped user units: it routes
  scheduling through the `presets` table. Presets carry scheduling keys (`defaultWanted`,
  `graphicalWanted`, `graphicalSession`) *and* service defaults (`restartOnFailure` =
  `Restart=on-failure` + `RestartSec=10`, `oneshot` = `Type=oneshot`); the caller's own
  `serviceConfig` key always wins, so a unit needing another delay just passes `RestartSec`.
- `mkUnitFromPresets` stays the value-level half (returns `Unit`/`Install`/`Service`) for callers
  that keep their own literal `systemd.user.services.<name>` key.
- Manage services via `systemctl --user start|stop|status <unit>`, logs via
  `journalctl --user -u <unit>`.

## Pitfalls found while wiring monitoring and post-boot

Post‑Boot Systemd Target

- Don’t add `After=graphical.target` to the `post-boot.target` itself; `graphical.target` already
  wants `post-boot.target`. Adding `After=graphical.target` on the target creates an ordering cycle.
- When deferring services to post‑boot, avoid blanket `After=graphical.target` in the helper that
  attaches units to `post-boot.target`. Let the target be wanted by `graphical.target`, and only add
  specific `After=` edges per service if strictly required (never the target itself).

Wi‑Fi via iwd profile

- The base network module installs iwd tooling but sets `networking.wireless.iwd.enable = false` so
  wired hosts don’t start it needlessly.
- To give a host Wi‑Fi controls, toggle `profiles.network.wifi.enable = true;` (e.g. inside
  `hosts/<name>/networking.nix`) instead of hand-written `lib.mkForce` overrides.

Prometheus PHP‑FPM Exporter

- The `php-fpm-exporter` monitoring module has been removed. Prometheus server is disabled in this
  configuration, and the exporter depended on `config.services.prometheus`.
