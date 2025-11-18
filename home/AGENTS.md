# Agent Guide (Home Manager repo)

This repo is configured for Home Manager + flakes with a small set of helpers to keep modules
consistent and activation quiet. This page shows what to use and how to validate changes.

## Helpers & Conventions

- Locations

  - Core helpers: `modules/lib/neg.nix`
  - XDG file helpers: `modules/lib/xdg-helpers.nix`
  - Features/options: `modules/features.nix`

- Package availability

  - Before suggesting or adding any `pkgs.*`/`nodePackages_*` dependency, confirm the attribute
    exists with `nix search` (or an equivalent eval) against the repo’s flake. Only move forward
    when the package is present in the current channel.

- QML best practices

  - Whenever you touch QML/Qt Quick files, stick to the upstream Qt guidelines and well-known best
    practices: keep components small and declarative, lean on property bindings instead of
    imperative logic, avoid binding loops/global JS helpers, and prefer type-safe properties and
    explicit signal handlers. Treat those guides as the source of truth and apply them wherever
    applicable in this repo.
  - Assume Qt 6+ features: review the latest Qt 6 porting notes and Quickshell release notes/docs
    before suggesting changes so you stay aligned with new APIs and incompatibilities.
  - (Tooling note) Automated QML linters/format checkers are currently unavailable; focus on the
    style/conventions above until the validation path is restored.

- XDG helpers (preferred)

  - Config text/link: `xdg.mkXdgText`, `xdg.mkXdgSource`

  - Data text/link: `xdg.mkXdgDataText`, `xdg.mkXdgDataSource`

  - Cache text/link: `xdg.mkXdgCacheText`, `xdg.mkXdgCacheSource`

  - Use these instead of ad‑hoc shell to avoid symlink/dir conflicts at activation.

  - JSON convenience: `xdg.mkXdgConfigJson`, `xdg.mkXdgDataJson`

    - Example:

      ```nix
      xdg.mkXdgConfigJson "fastfetch/config.jsonc" {
        logo = {source = "$XDG_CONFIG_HOME/fastfetch/skull";};
      }
      ```

  - TOML convenience: `xdg.mkXdgConfigToml`, `xdg.mkXdgDataToml`

    - Import with pkgs: `let xdg = import ../../lib/xdg-helpers.nix { inherit lib pkgs; };`

    - Example:

      ```nix
      xdg.mkXdgConfigToml "myapp/config.toml" {
        core.enable = true;
        paths = ["a" "b"];
      }
      ```

- Conditional sugar (from `lib.neg`)

  - `mkWhen cond attrs` / `mkUnless cond attrs` — thin wrappers over `lib.mkIf`.
    - Example:

      ```nix
      lib.mkMerge [
        (config.lib.neg.mkWhen config.features.web.enable {
          programs.aria2.enable = true;
        })
      ]
      ```

- Activation helpers (from `lib.neg`)

  - `mkEnsureRealDir path` / `mkEnsureRealDirsMany [..]` — ensure real dirs before linkGeneration
  - `mkEnsureAbsent path` / `mkEnsureAbsentMany [..]` — remove conflicting files/dirs pre‑link
  - `mkEnsureDirsAfterWrite [..]` — create runtime dirs after writeBoundary
  - `mkEnsureMaildirs base [boxes..]` — create Maildir trees after writeBoundary
  - Aggregated XDG fixups were removed to reduce activation noise.
    - Prefer per‑file `force = true` on `home.file` or `xdg.(config|data|cache)File` entries if you
      need to overwrite a conflicting path.
    - Keep modules simple: declare targets via `xdg.mkXdg*` helpers and rely on Home Manager to
      manage links.
  - Common user paths prepared via:
    - `ensureCommonDirs`, `cleanSwayimgWrapper`, `ensureGmailMaildirs`
  - Local bin wrappers (safe ~/.local/bin scripts):
    - `config.lib.neg.mkLocalBin name text` — removes any conflicting path before linking and marks
      executable.

    - Example:

      ```nix
      config.lib.neg.mkLocalBin "rofi" ''
        #!/usr/bin/env bash
        set -euo pipefail
        exec ${pkgs.rofi-wayland}/bin/rofi "$@"
      ''
      ```

- Systemd (user) sugar:

  - In this repository, use the stable pattern:
    `lib.mkMerge + config.lib.neg.systemdUser.mkUnitFromPresets`.

  - The "simple" helpers (`mkSimpleService`, `mkSimpleTimer`, `mkSimpleSocket`) are available but
    can trigger HM‑eval recursion in some contexts. Default policy: do not use them in modules;
    instead assemble units as below.

  - Example (service):

    ```nix
    systemd.user.services.my-service = lib.mkMerge [
      {
        Unit = { Description = "My Service"; };
        Service.ExecStart = "${pkgs.foo}/bin/foo --flag";
      }
      (config.lib.neg.systemdUser.mkUnitFromPresets { presets = ["defaultWanted"]; })
    ];
    ```

  - Example (timer):

    ```nix
    systemd.user.timers.my-timer = lib.mkMerge [
      {
        Unit.Description = "My Timer";
        Timer = { OnBootSec = "2m"; OnUnitActiveSec = "10m"; Unit = "my-timer.service"; };
      }
      (config.lib.neg.systemdUser.mkUnitFromPresets { presets = ["timers"]; })
    ];
    ```

- Rofi wrapper (launcher)

  - A local wrapper is installed to `~/.local/bin/rofi` to provide safe defaults and consistent UX:
    - Adds `-no-config` unless the caller explicitly passes `-config`/`-no-config`.
    - Enables auto-accept by default (`-auto-select`). Disable per-call with `-no-auto-select`.
    - Ensures Ctrl+C cancels (`-kb-cancel "Control+c,Escape"`) and frees it from the default copy
      binding (`-kb-secondary-copy ""`).
    - Resolves themes passed via `-theme <name|name.rasi>` relative to `$XDG_DATA_HOME/rofi/themes`
      or `$XDG_CONFIG_HOME/rofi`.
    - Computes offsets for top bars via Quickshell/Hyprland metadata when not provided.
  - Guidance:
    - Keep rofi invocations plain (e.g., `rofi -dmenu ... -theme menu`). Avoid repeating
      `-no-config`/`-kb-*` in configs.
    - If you must override keys for a particular call, pass your own `-kb-*` flags — the wrapper
      will not inject defaults twice.

- Editor shim (`v`)

  - A tiny wrapper `~/.local/bin/v` launches Neovim (`nvim`). Prefer `v` in bindings/commands where
    a short editor command is desirable.
  - Git difftool/mergetool examples in this repo now use `nvim` directly; legacy `~/bin/v` is no
    longer referenced.

- Soft migrations (warnings):

  - Prefer `{ warnings = lib.optional cond "message"; }` to emit non‑fatal guidance.

  - Avoid referencing `config.lib.neg` in warnings to keep option evaluation acyclic.

  - Example (MPD path change):

    ```nix
    {
      warnings =
        lib.optional (config.services.mpd.enable or false)
        "MPD dataDir moved to $XDG_STATE_HOME/mpd; consider migrating from ~/.config/mpd.";
    }
    ```

- Commit messages *(RU transliteration: "Kommit-messidzhi")*:

  - Keep the format `[scope] brief summary`. Scope is a short noun/phrase wrapped in brackets (e.g.
    `[mcp] add foo server`, `[quickshell] reuse capsule row`) so changes stay easy to grep by area.

  - If multiple areas are touched, combine them with `/` (`[mcp/gui] …`) or pick the most general
    scope. Always include the brackets and keep the description outside of them.

  - Template and tips:

    - Keep conditions cheap to evaluate (avoid invoking helpers from `config.lib.neg`).

    - Phrase messages with clear destination and rationale (XDG compliance, less activation noise,
      etc.).

    - Example:

      ```nix
      let
        old = "${config.home.homeDirectory}/.config/app";
        target = "${config.xdg.stateHome}/app";
        needsMigration = (cfg.enable or false) && ((cfg.dataDir or old) == old);
      in {
        warnings =
          lib.optional needsMigration
          (
            "App dataDir uses ~/.config/app. Migrate to $XDG_STATE_HOME/app ("
            + target
            + ") for XDG compliance."
          );
      }
      ```

## App Notes

- aria2 (download manager)

  - Keep configuration minimal and XDG-compliant:
    - Use `programs.aria2.settings` with only the essentials:
      - `dir = "${config.xdg.userDirs.download}/aria"` — downloads under XDG Downloads.
      - `enable-rpc = true` — enable RPC for UIs/integrations.
      - `save-session`/`input-file = "$XDG_DATA_HOME/aria2/session"` — persist resume state.
      - `save-session-interval = 1800`.
    - Ensure the session file exists via XDG helper (no ad‑hoc prestart scripts):
      - `(xdg.mkXdgDataText "aria2/session" "")`.
    - Systemd (user) service should be simple:
      - Example:

        ```nix
        Service.ExecStart =
          "${pkgs.aria2}/bin/aria2c --conf-path=$XDG_CONFIG_HOME/aria2/aria2.conf";
        ```

      - Attach preset:
        `(config.lib.neg.systemdUser.mkUnitFromPresets { presets = ["graphical"]; })`.
  - Avoid `ExecStartPre` mkdir/touch logic — prefer XDG helpers and per‑file `force = true`; reduces
    activation noise.

- Telegram MCP servers

  - `telegram` (personal account bridge, TDLib/gotd):
    - Env: export `TG_APP_ID`, `TG_API_HASH`; run
      `telegram-mcp auth --app-id ... --api-hash ... --phone ...` once to create
      `$XDG_DATA_HOME/mcp/telegram/session.json` (autoprovisioned by HM).
    - Full access to personal dialogs, drafts, and read states — only use when policy allows sharing
      the entire account context.
  - `telegram-bot` (Bot API only):
    - Env: `TELEGRAM_BOT_TOKEN` from `@BotFather`; no phone login or session files.
    - Limited tools (`get_bot_info`, `send_message`, `get_updates`, `forward_message`) for
      alerting/automation in bot chats; cannot read private user dialogs.
  - Choose the bridge that matches the required scope: bot token for channel/automation work, full
    account for inbox assistants.

- MCP: Gmail/Calendars/Mail/DevTools

  - `gmail` (Gmail API w/ style guide + draft tools):
    - Env: `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_REFRESH_TOKEN`, `OPENAI_API_KEY`.
    - Stores tokens + style guide under `~/.auto-gmail`; HM pre-creates the dir so the Go binary can
      persist state in pure builds.
    - Use this when you need Gmail-specific search, thread metadata, and draft synthesis; IMAP is
      faster to wire up but cannot access Gmail resources like style guides.
  - `google-calendar` (teren-papercutlabs/gcal-mcp):
    - Env: `GCAL_CLIENT_ID`, `GCAL_CLIENT_SECRET`, `GCAL_REFRESH_TOKEN` (optional
      `GCAL_ACCESS_TOKEN`), `GCAL_CALENDAR_ID` to preselect calendars.
    - Binary lives in the Nix store, so OAuth flows must inject refresh tokens; interactive logins
      cannot write to `$out` (documented limitation).
  - `imap-mail` / `smtp-mail` (generic mailboxes):
    - IMAP env: `IMAP_HOST`, `IMAP_PORT`, `IMAP_USERNAME`, `IMAP_PASSWORD`, `IMAP_USE_SSL`.
    - SMTP env: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM_ADDRESS`,
      `SMTP_USE_TLS`, `SMTP_USE_SSL`, optional `SMTP_BEARER_TOKEN`.
    - Use IMAP/SMTP when you want provider-agnostic mail access or service accounts; Gmail server
      remains superior for Gmail-native labels + drafts.
  - `github` vs `gitlab`:
    - GitHub env: `GITHUB_TOKEN` (PAT or fine-grained token), optional
      `GITHUB_HOST`/`GITHUB_TOOLSETS`/`GITHUB_READ_ONLY` toggles. Requires the `stdio` subcommand;
      PAT scopes should cover repos/issues/actions per need.
    - GitLab env: `GITLAB_TOKEN`, `GITLAB_API_URL`, optional `GITLAB_PROJECT_ID`,
      `GITLAB_ALLOWED_PROJECT_IDS`, `GITLAB_READ_ONLY_MODE`, `USE_GITLAB_WIKI`, `USE_MILESTONE`,
      `USE_PIPELINE`. Use OAuth only if you can persist tokens outside the store.
    - GitHub server gives you Copilot-style repo/PR/actions tooling; GitLab fork adds
      wiki/milestone/pipeline operations for self-hosted instances.
  - `discord`:
    - Env: `DISCORD_BOT_TOKEN` (wired into upstream `DISCORD_TOKEN`), optional `DISCORD_CHANNEL_IDS`
      to restrict usage at the policy layer.
    - Bot-only bridge: can read and write in joined guild channels; no DM access.
  - `media-control`:
    - Optional env overrides: `MCP_MPD_HOST`/`MCP_MPD_PORT` for MPD, `PIPEWIRE_SINK` for the target
      sink, `WPCTL_BIN` to point at a different `wpctl` binary (defaults to
      `${pkgs.wireplumber}/bin/wpctl`).
    - Includes tools for playback + volume UX:
      - `get_playback_status` — current MPD state (artist/title/queue/time/repeat flags).
      - `control_playback` — `play`/`pause`/`toggle`/`next`/`previous`/`stop`/`clear` operations.
      - `queue_artist` — bulk-add all tracks from an artist (with optional clear/autoplay).
      - `adjust_volume` — wraps PipeWire `wpctl` to set/change/mute/toggle sink volume.
    - Requires the MPD feature stack + PipeWire (Hyprland sessions already expose
      `@DEFAULT_AUDIO_SINK@`).
  - `media-search`:
    - Env defaults (`MCP_MEDIA_SEARCH_PATHS`) point to Documents/notes/Obsidian/Screenshots;
      override to add extra roots. Optional `MCP_MEDIA_SEARCH_CACHE` speeds up repeat OCR runs,
      `MCP_MEDIA_OCR_LANG` sets Tesseract languages, `TESSERACT_BIN` swaps the binary if needed.
    - Tools:
      - `list_documents` — enumerate indexed files with type/size metadata.
      - `search_snippets` — fuzzy search across text/OCR output and return scored snippets.
      - `extract_document` — dump (truncated) text for a given document id.
    - Supports Markdown/plain text, PDFs, and PNG/JPEG/WebP/TIFF screenshots via Tesseract OCR.
      Cache lives under `$XDG_CACHE_HOME/mcp/media-search`.
  - `agenda`:
    - Env defaults pick up Vdirsyncer/Khal calendars: `MCP_AGENDA_ICS_PATHS` (colon-separated) and
      store ad-hoc notes in `$XDG_DATA_HOME/mcp/agenda/notes.json`. Tune `MCP_AGENDA_LOOKAHEAD_DAYS`
      and `MCP_AGENDA_TZ` per user.
    - Tools:
      - `list_upcoming` — timeline of upcoming events within a configurable window.
      - `find_free_windows` — search for open slots between start/end with a duration constraint.
      - `add_note_event` — append a lightweight reminder/note without touching calendar apps.
    - Reads `.ics` files (including per-event dirs) plus the notes JSON; all timestamps normalized
      to the user’s timezone.
  - `knowledge-vector`:
    - Env: `MCP_KNOWLEDGE_PATHS` (Documents/notes/code roots), optional `MCP_KNOWLEDGE_CACHE`
      (defaults to `$XDG_CACHE_HOME/mcp/knowledge`), `MCP_KNOWLEDGE_MODEL` (defaults to
      `sentence-transformers/all-MiniLM-L6-v2`), `MCP_KNOWLEDGE_EXTRA_PATTERNS` for extra file
      globs.
    - Tools:
      - `list_documents` — metadata for indexed files + chunk counts.
      - `vector_search` — returns top-k semantic matches with path/title/snippets.
      - `add_manual_snippet` — inject ad-hoc context (stored under the cache dir).
    - Indexes Markdown/plain text/code and PDFs (text extracted via pdfminer). Embeddings are cached
      to speed up restarts; manual snippets persist alongside the cache.
  - Browser automation (`playwright`, `chromium`):
    - `playwright`: persists profile/output under `$XDG_DATA_HOME/mcp/playwright`, browsers cached
      in `$XDG_CACHE_HOME/ms-playwright`. Pass `PLAYWRIGHT_HEADLESS` or `PLAYWRIGHT_CAPS` via env to
      tweak launch flags; CLI args `--user-data-dir/--output-dir` are pre-set.
    - `chromium`: uses `CHROMIUM_USER_DATA_DIR=$XDG_DATA_HOME/mcp/chromium/profile`; optional
      `CHROMIUM_PATH` to point at preinstalled builds.
    - Combine them when you need both Playwright’s structured accessibility snapshots and
      lower-level CDP control (Chromium) for debugging.
  - `meeting-notes`:
    - FastMCP server that writes timelines + analytics into `~/.claude/session-notes`; HM ensures
      the tree exists so pure builds succeed.
    - No secrets required; useful for keeping long-running coding sessions summarized for later
      recall.

- rofi (launcher)

  - Use the local wrapper `rofi` from `~/.local/bin` (PATH is set so it takes precedence).
  - Do not pass `-kb-cancel` or `-no-config` unless you need custom behavior; the wrapper ensures
    sane defaults and Ctrl+C cancellation.
  - Themes live under `$XDG_CONFIG_HOME/rofi` and `$XDG_DATA_HOME/rofi/themes`; `-theme menu` works
    out of the box.

- Floorp (defaults & chrome tips)

  - Defaults in this repo aim for a quiet, private setup:
    - Strict content blocking (ETP) and DNS-over-HTTPS enabled via policies.
    - Telemetry, Studies, and Pocket disabled via policies.
    - New Tab (Activity Stream) cleaned: no sponsored tiles, Top Sites, Highlights, Top Stories, or
      Weather.
    - URL bar suggestions: Quicksuggest/trending disabled.
    - Native file picker via XDG portals enabled.
  - Chrome inspection: open `chrome://browser/content/browser.xhtml` in a tab and use DevTools
    (`Ctrl+Shift+I`) to probe selectors (bottom nav, urlbar chips, etc.). Close the tab when
    finished to avoid a background chrome document.

- systemd (user) presets

  - Always use `config.lib.neg.systemdUser.mkUnitFromPresets { presets = [..]; }` (recommended)
  - Typical presets:
    - Service in GUI session: `["graphical"]`
    - Wants network online: `["netOnline"]`
    - General user service: `["defaultWanted"]`
    - Timer: `["timers"]`
    - DBus socket ordering: `["dbusSocket"]`
  - Add extras only when needed: `after`, `wants`, `partOf`, `wantedBy`.

## Hyprland notes

- Autoreload is disabled to avoid inotify races during activation (`disable_autoreload = 1`).
- No activation‑time `hyprctl reload`; keep manual reload only (hotkey in `bindings.conf`).

## Commit Messages

- Format: `[scope] subject` (English, imperative).
  - Examples: `[activation] reduce noise`, `[features] add flag`, `[gui/hypr] normalize rules`.
  - Multi‑scope allowed: `[xdg][activation] ...`
  - Allowed exceptions: `Merge ...`, `Revert ...`, `fixup!`, `squash!`, `WIP`.
- Keep changes focused and minimal; avoid drive‑by fixes unless requested.

## Language & Comments

- English‑only for code comments, commit messages, and new docs by default.
  - Russian content belongs in dedicated translations only (e.g., `README.ru.md`).
  - Do not add Russian comments inside Nix modules or shell snippets.
- Comment style:
  - Keep comments concise; move long notes above the line they describe.
  - Target ~100 chars width (see STYLE.md) for readability in diffs.
  - Prefer actionable wording over narration.

## Quick Tasks

- Format: `just fmt` (wrapper around `nix fmt`)
- Checks: `just check` (flake checks, docs build)
- Lint only: `just lint` (statix, deadnix, shellcheck, ruff/black if present)
- Switch HM: `just hm-neg` (or `just hm-lite`)
- Git hooks: `just hooks-enable` (sets repo hooks path; pre-commit auto-runs `nix fmt`, skip with
  `SKIP_NIX_FMT=1`)

## Guard rails

- Don’t reintroduce Hyprland auto‑reload or activation reload hooks.
- For files under `~/.config` prefer XDG helpers + `config.lib.file.mkOutOfStoreSymlink` instead of
  ad‑hoc shell.
- Use feature flags (`features.*`) with `mkIf`; parent flag off implies children default to off.
- Quickshell: `modules/user/gui/quickshell/conf/Settings.json` is ignored; do not add it back.

## Validation

- Always end with a real build/test so regressions surface early; default to
  `nix build .#homeConfigurations.neg.activationPackage` (or `just check` when broader coverage
  matters) and mention the outcome if you have to skip it.
- New files you add must be committed or staged before building; otherwise the flake source will
  omit them and any derivation referencing them will fail.
- Local eval: `nix flake check -L` (may build small docs/checks)
- Fast feature view (no build): build `checks.x86_64-linux.hm-eval-neg-retro-off` and inspect JSON
- HM switch (live): `home-manager switch --flake .#neg`
