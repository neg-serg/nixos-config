# Coding Style (Nix / Home Manager)

See also: ../docs/manual/manual.en.md for a short guide on helpers, activation aggregators, systemd presets, commit
message format, and quick `just` commands.

## Formatting (alejandra)

- Run `nix fmt` (or `just fmt`) before committing. Both invoke treefmt which, in turn, runs
  `alejandra -q` with the repo defaults.
- Enable the provided git hooks (`just hooks-enable`) so `nix fmt` runs automatically at pre-commit;
  export `SKIP_NIX_FMT=1` to bypass in emergencies.
- Indentation is always 2 spaces. Function arguments, `let` bindings, and attribute sets get split
  across lines at that depth.
  - Skip manual column alignment; alejandra removes it.
- Lists with non-trivial elements (attrsets, long strings, nested lists) are expanded to one item
  per line.
  - Short literals may stay inline—let the formatter decide.
- Attribute sets grow vertically as soon as they hold more than one simple binding.
  - One-liners such as `{ name = "foo"; }` can remain inline, while multi-field sets become
    block-styled.
- Comments stay attached to the expression they precede.
  - Keep remarks above the line instead of inline to avoid awkward splits.
- Spacing is normalised: redundant blank lines vanish, `inherit` statements tighten up, and trailing
  spaces disappear.
  - If a hunk looks noisy, re-run `nix fmt` rather than tweak whitespace by hand.

In short: trust the formatter. Write readable Nix, run `nix fmt`, and let alejandra settle
whitespace and wrapping.

- Markdown

  - `just fmt` (treefmt) now runs `mdformat --wrap 100` on all `*.md`/`*.markdown` files to keep
    prose, lists, and tables consistent.
  - `just lint-md` wraps `markdownlint` (using `.markdownlint.yaml`) so you can check headings,
    fences, and wrapping when needed without auto-fixes.

- with pkgs usage

  - Prefer explicit `pkgs.*` items in lists (lint enforces: no `with pkgs; [ ... ]`).
  - It’s acceptable to use `with pkgs;` for building local attrsets (e.g.,
    `groups = with pkgs; { a = [foo]; b = [bar]; };`), but avoid leaking it beyond the immediate
    scope.

- Line width (~100 chars)

  - Target ~100 characters per line. This keeps diffs readable.
  - Keep end-of-line comments short; if they don't fit, move them above the line.
  - Tip: set an editor ruler at 100 to help keep lines concise.
  - Example:
    - Good: `"reaper" # DAW`
    - Also good (longer note moved above): `# Compute DR14 (Pleasurize Music Foundation procedure)`
      `"dr14_tmeter"`

- Comments

  - Prefer concise, recognizable terms (e.g., "DAW", "modular synth").
  - Put long comments above the line they describe (not inline).
  - Avoid repeating obvious context (module name or path) in comments.

- Options

  - Declare feature options centrally (see `modules/features.nix`).
  - Gate per-area configuration via `mkIf` using `features.*` flags.

- Assertions

  - Provide actionable messages when extra inputs or packages are required by a flag.

- Prefer non-blocking warnings via `warnings = lib.optional cond "..."` for soft migrations and
  deprecations.

  - Example: `{ warnings = lib.optional cond "<what to change and how>"; }`
  - Template:
    - Keep the condition cheap and avoid touching `config.lib.neg` inside the warning to prevent
      evaluation cycles.

    - Use explicit, actionable wording (what changed, where to move files, and why).

    - Example:

      ```nix
      let
        old = "${config.home.homeDirectory}/.config/foo";
        new = "${config.xdg.stateHome}/foo";
        needsMigration = (cfg.enable or false) && ((cfg.dataDir or old) == old);
      in {
        warnings =
          lib.optional needsMigration
          "Foo dataDir uses ~/.config/foo. Consider migrating to $XDG_STATE_HOME/foo (${new}).";
      }
      ```

- Naming

  - Use camelCase for extraSpecialArgs and internal aliases (e.g., `yandexBrowser`, `iosevkaNeg`).

- Structure

  - Factor large package lists into local `groups = { ... }` sets.
  - Use `config.lib.neg.mkEnabledList` to flatten groups based on flags.
    - Prefer over manual chains of `lib.optionals` for readability and consistency.
    - Pattern: `home.packages = config.lib.neg.mkEnabledList config.features.<area> groups;`
    - For nested scopes (e.g., Python withPackages) build `groups` first, then flatten.
  - For systemd user units, prefer `config.lib.neg.systemdUser.mkUnitFromPresets` to set
    `After`/`Wants`/`WantedBy`/`PartOf` via presets instead of hardcoding targets in each module.
    Extend with `after`/`wants`/`partOf`/`wantedBy` args only for truly extra dependencies.

- Systemd (user) sockets/paths

  - Apply the same presets helper to `systemd.user.sockets.*` and `systemd.user.paths.*`.

  - Sockets: tie activation to `sockets.target`; add `wantedBy = ["sockets.target"]` explicitly.

    - Example:

      ```nix
      systemd.user.sockets.my-sock =
        lib.recursiveUpdate
          {Unit.Description = "My socket"; Socket.ListenStream = "%t/my.sock";}
          (config.lib.neg.systemdUser.mkUnitFromPresets {
            presets = ["socketsTarget"];
            wantedBy = ["sockets.target"];
          });
      ```

  - Paths: usually want `default.target` so the path unit is active in the session.

    - Example:

      ```nix
      systemd.user.paths.my-path =
        lib.recursiveUpdate
          {
            Unit.Description = "Watch foo";
            Path.PathChanged = "%h/.config/foo/config";
          }
          (config.lib.neg.systemdUser.mkUnitFromPresets {presets = ["defaultWanted"];});
      ```

- Systemd sugar (policy in this repo)

  - Default policy: use the stable pattern:
    `lib.mkMerge + config.lib.neg.systemdUser.mkUnitFromPresets`.

    - Example (service):

      ```nix
      systemd.user.services.foo = lib.mkMerge [
        {
          Unit.Description = "Foo";
          Service.ExecStart = "${pkgs.foo}/bin/foo";
        }
        (config.lib.neg.systemdUser.mkUnitFromPresets {presets = ["defaultWanted"];})
      ];
      ```

    - Example (timer):

      ```nix
      systemd.user.timers.foo = lib.mkMerge [
        {
          Unit.Description = "Timer: foo";
          Timer = {
            OnBootSec = "2m";
            OnUnitActiveSec = "10m";
            Unit = "foo.service";
          };
        }
        (config.lib.neg.systemdUser.mkUnitFromPresets {presets = ["timers"];})
      ];
      ```

  - The "simple" helpers (`mkSimpleService`, `mkSimpleTimer`, `mkSimpleSocket`) are available, but
    in this module tree they sometimes trigger HM‑eval recursion. Use them only when you are certain
    they do not introduce a cycle; otherwise prefer `mkUnitFromPresets`.

- Commit messages

  - Use bracketed scope: `[scope] subject` (English imperative, concise).
    - Examples: `[activation] add guards for xyz`, `[docs] update OPTIONS.md`.
    - Multi-scope allowed: `[gui/hypr][rules] normalize web classes`.
  - Exceptions allowed: `Merge ...`, `Revert ...`, `fixup!`, `squash!`, `WIP`.
  - A `commit-msg` hook enforces this locally (see modules/dev/git/default.nix).

- XDG file helpers

  - Prefer the pure helpers from `modules/lib/xdg-helpers.nix` (import locally):
    - Config (text/link): `mkXdgText`, `mkXdgSource`
    - Data (text/link): `mkXdgDataText`, `mkXdgDataSource`
    - Cache (text/link): `mkXdgCacheText`, `mkXdgCacheSource`
    - They ensure parent directories are real dirs (not symlinks), remove any existing target
      (symlink, regular file, or directory), then write/link the file. This prevents activation
      failures when a directory exists where a file/link is expected.
  - Examples:
    - Config text: `(xdg.mkXdgText "nyxt/init.lisp" "... Lisp ...")`

    - Config source:

      ```nix
      xdg.mkXdgSource "swayimg" {
        source =
          config.lib.file.mkOutOfStoreSymlink
          "${config.neg.dotfilesRoot}/nix/.config/home-manager/modules/media/images/swayimg/conf";
        recursive = true;
      }
      ```

    - Data keep: `(xdg.mkXdgDataText "ansible/roles/.keep" "")`

    - Cache keep: `(xdg.mkXdgCacheText "ansible/facts/.keep" "")`

    - Config JSON:

      ```nix
      xdg.mkXdgConfigJson "fastfetch/config.jsonc" {
        logo = {source = "$XDG_CONFIG_HOME/fastfetch/skull";};
      }
      ```

    - Data JSON: `(xdg.mkXdgDataJson "aria2/state.json" { version = 1; })`

    - Config TOML: `(xdg.mkXdgConfigToml "app/config.toml" { enable = true; nested.option = 1; })`

    - Data TOML: `(xdg.mkXdgDataToml "app/state.toml" { version = 1; list = [1 2 3]; })`
  - Import tip (robust for docs eval):
    - If JSON/TOML helpers are needed, include `pkgs`:
      - From `modules/dev/...` or `modules/media/...`:
        `let xdg = import ../../lib/xdg-helpers.nix { inherit lib pkgs; };`
      - From `modules/user/mail/...`:
        `let xdg = import ../../../lib/xdg-helpers.nix { inherit lib pkgs; };`
    - Otherwise (no TOML/JSON needed), `inherit lib` is enough.

- Merging attrsets

  - Prefer `lib.mkMerge [ a b ... ]` over top-level `//` for combining module fragments.

  - Keep each logical piece in its own attrset within `mkMerge` (e.g., package set, xdg helpers,
    systemd units).

  - Conditional sugar: use `config.lib.neg.mkWhen` / `config.lib.neg.mkUnless` instead of bare
    `lib.mkIf` to improve scanability.

  - Example:

    ```nix
    lib.mkMerge [
      (config.lib.neg.mkWhen config.features.web.enable {programs.aria2.enable = true;})
      (config.lib.neg.mkUnless config.features.gui.enable {xdg.mime.enable = false;})
    ]
    ```

- Runtime directories (first-run safety)

  - Ensure required runtime/state directories exist before services start or files are written.
    - After write:
      `home.activation.ensureDirs = config.lib.neg.mkEnsureDirsAfterWrite ["$XDG_STATE_HOME/zsh"];`
    - Real config dir:
      `home.activation.fixFoo = config.lib.neg.mkEnsureRealDir "${config.xdg.configHome}/foo";`
    - Maildir trees: `config.lib.neg.mkEnsureMaildirs "$HOME/.local/mail/gmail" ["INBOX" ...]`
  - Use these in addition to xdg helpers when apps require extra runtime dirs (sockets, logs,
    caches) outside XDG config files.

- Local bin wrappers

  - Prefer `config.lib.neg.mkLocalBin` for `~/.local/bin/<name>` scripts to avoid path conflicts
    during activation.

  - Example:

    ```nix
    config.lib.neg.mkLocalBin "rofi" ''
      #!/usr/bin/env bash
      set -euo pipefail
      exec ${pkgs.rofi-wayland}/bin/rofi "$@"
    ''
    ```

  - This removes any existing path (file/dir/symlink) before linking and marks the target
    executable.

  - Note: in rare cases (for example, due to specific module/merge ordering), `mkLocalBin` may
    trigger HM‑eval recursion. In such places it is acceptable to use the direct equivalent via
    `home.file` plus an activation guard (see rofi/swayimg modules). For new wrappers, try
    `mkLocalBin` first.

- Rofi usage conventions

  - Prefer calling `rofi` plainly (e.g., `rofi -dmenu ... -theme menu`). The local wrapper enforces:
    - `-no-config` by default unless the caller provides `-config`/`-no-config`.
    - `Ctrl+C` to cancel: injects `-kb-secondary-copy ""` and `-kb-cancel "Control+c,Escape"` when
      not explicitly provided.
    - Theme path resolution for `-theme <name|name.rasi>` relative to XDG locations.
  - Avoid duplicating these flags in module code to keep configs concise and prevent "already bound"
    warnings.
  - If a specific invocation requires a custom keymap, pass your own `-kb-*` flags; the wrapper will
    not add defaults twice.

- Systemd (user) sugar

  - For simple services use `config.lib.neg.systemdUser.mkSimpleService` instead of repeating the
    same boilerplate.

    - Example:

      ```nix
      config.lib.neg.systemdUser.mkSimpleService {
        name = "aria2";
        description = "aria2 download manager";
        execStart = "${pkgs.aria2}/bin/aria2c --conf-path=$XDG_CONFIG_HOME/aria2/aria2.conf";
        presets = ["graphical"];
      }
      ```

  - Under the hood it composes `Unit/Service` and applies `mkUnitFromPresets` for
    `After/Wants/WantedBy/PartOf`.

- Out-of-store dotfile links

  - For live-editable configs stored in this repo, use
    `config.lib.file.mkOutOfStoreSymlink "${config.neg.dotfilesRoot}/<path/in/repo>"`.
  - Combine with `xdg.mkXdgSource` for guards and correct placement under XDG.

- Imports (xdg helpers) — convention

  - Use a local binding near the top of a module:
    - `let xdg = import ../../lib/xdg-helpers.nix { inherit lib; }; in lib.mkMerge [ ... ]`
  - Choose `../../` depth according to the module path.
