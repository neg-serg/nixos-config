#
# pleamar shell (features.gui.pleamar)
# (moved out of the docs tree; keep it in sync with the code it describes)
#
#
# Desktop shell: pleamar (https://github.com/k4ditano/pleamar) is a Rust Wayland runtime with a
# declarative `.plm` scene language. It replaced the Quickshell shell area by area — bar, panels,
# notifications, toast, launcher, and since 2026-11-02 the login screen — and every scene is an
# independent process with its own unit, so one can restart or be measured without touching the
# others.
#
# **On** since the parity push: `features.gui.pleamar.enable = true` in `hosts/trantor/default.nix`,
# and this module's units are the session's shell. It is the only shell in the tree: the Quickshell
# module was deleted with its tree on 2026-11-02, so there is no second panel to fall back to — but
# the scenes and `pkgs.pleamar` stay either way, and flipping the flag off just stops the scenes.
#
# ## Sources of truth
#
# | what                                                             | where                                           |
# | ---------------------------------------------------------------- | ----------------------------------------------- |
# | scene layout, running one scene by hand, measurement             | `files/pleamar/README.md`                       |
# | frozen scene/IPC catalog, palette and capsule APIs, label policy | `files/pleamar/docs/INTERFACES.md`              |
# | phases, gates, budgets, open work                                | `.agent/plans/2026-10-16-pleamar-superplan.xml` |
# | module wiring, units, guards                                     | `modules/user/nix-maid/gui/pleamar.nix`         |
#
# The `.plm` files live in `files/pleamar/shells/<scene>/<scene>.plm`; directory name, scene name and
# IPC name are the same string.
#
# ## Units and guards (when the flag is on)
#
# - `pleamar-<scene>.service` for every scene in `pleamarScenes` (`bar`, `panels`, `notifications`,
#   `toast`, `launcher`, `widgets`, `osd`), each running
#   `pleamar --scene ~/.config/pleamar/shells/<scene>/<scene>.plm --no-hud` with memory/CPU caps.
#   `overlay` is an on-demand unit (`pleamarOnDemandUnits`) and `proof` is not started at all;
#   `overview` is a deliberate omission (a resident process for one IPC verb costs more than the
#   bind). `lock` gets a unit too, but from `pleamarOnDemandUnits`: the scene is born locked
#   (`fact locked = true`), so autostart would put the pleamar lock screen in front of every login
#   before PH3-L's PAM matrix has been run by hand. Start it when it is wanted —
#   `systemctl --user start pleamar-lock.service`.
# - `pleamar-health` + `pleamar-health.timer` — hang watchdog: probes every scene in
#   `pleamarHealthScenes` (the bar and the panels; 2-minute period, first run after 5 minutes) and
#   restarts the one that stops answering.
# - `pleamar-theme` — runs the theme pipeline (packages/pleamar-theme) on every wallpaper
#   change, writing `~/.config/pleamar/theme.plm`; `pleamar-themes` writes the same file from a
#   hand-written theme file (`list`, `apply`, `show`), so a theme is a file, not a wallpaper.
# - `pleamar-cleanup-symlink` — removes stale deployed links; without it a scene dies on a missing
#   `.plm` between cleanup and activation.
# - Login-phase guard: while `%t/pleamar-login/login-phase` exists the login layer owns the screen
#   (`pleamar-login-layer`, which runs the lock scene by hand) and no session scene may start;
#   systemd re-evaluates the condition once the marker is gone.
#
# ## Enable / disable
#
#     # enable
#     $EDITOR hosts/trantor/default.nix     # features.gui.pleamar.enable = true;
#     $ nixos-rebuild switch --flake .#trantor --option substitute false
#     # then log out and back in: the scenes are session units, not a live restart
#
# Flipping the flag off stops the scenes on their own, and nothing takes the screen
# afterwards: there is no second shell left to fall back to.
#
# ## Gate
#
# `scripts/dev/check-plm.sh` validates every scene and runs as part of `just lint`, so a broken `.plm`
# fails before a switch rather than at login.
#
# ## Open state (2026-10-17)
#
# Notifications still miss their budget (1.0 % of a core against the 0.5 % target) and
# `tests/evidence/` is missing, so the G3/SC2 gates are unproven. The plugin phase (PH3-P) has
# landed six plugins. The analyser in the media card is the one unverified path: `spectrum.luau`
# only heard about `media` through its watch, and a track that was already playing when the scene
# started produces no change event — it now asks once at load and polls every two seconds while
# nothing plays. Confirm cava is a child of the scene after a fresh start before trusting it; the
# superplan carries the per-phase status.

{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  # Module-shaped systemd user units (lib/systemd-user.nix)
  systemdUser = config.lib.neg.systemdUser;

  # Feature gate (single source: config.lib.neg.pleamarEnabled)
  pleamarEnabled = config.lib.neg.pleamarEnabled;

  # The wallpaper deck (features.gui.wallpaperPicker) is a scene of this module: its flag decides
  # whether the scene's unit and its helper commands exist at all.
  pickerEnabled = config.lib.neg.wallpaperPickerEnabled;

  # ── Scenes ────────────────────────────────────────────────────────────────
  # The single scene list: the per-scene units, the deployed links and the
  # generated autostart file all derive from it. Later phases append names here
  # (bar, notifications, …) — nothing else in this module needs editing.
  # `proof` is the PH0 pipeline probe: it stays out of autostart on purpose.
  # `overview` is deliberately absent: its first version is a thin `hypr-expo toggle`
  # and a resident process just to answer one IPC verb would cost more than the bind;
  pleamarScenes = [
    "bar"
    "panels"
    "notifications"
    "toast"
    "launcher"
    # The desktop widgets (clock, now-playing, quote, system monitor, analyser): a
    # bottom layer over the wallpaper, under every window. Its own scene, not part
    # of the bar, because it draws when no panel is open.
    "widgets"
    # The volume/brightness pill: watches `audio` and `brightness` and shows itself, so it
    # is resident — nothing else could start it on the change that has to raise it.
    "osd"
  ];

  # Scenes that must come back from *any* exit, not only a crash: the bar and
  # the ones that live for the whole session. `panels` is deliberately not
  # here — a drawer scene may close itself and must not be resurrected.
  pleamarResidentScenes = [
    "bar"
    "panels" # a compositor reload closes its layer surfaces, and the drawer scene exits 0
    "notifications"
    "toast"
    "launcher"
    # The desktop layer is lost the same way a bar is when the compositor closes
    # its surfaces; nothing else would bring it back. The OSD is a scene whose whole
    # job is to be there when the volume moves, so it comes back too.
    "widgets"
    "osd"
  ];

  # The scenes the hang watchdog probes. A wedged bar is the obvious one, but the panels scene draws
  # every drawer, and a wedged panels looks like a dead shell while the bar keeps ticking — which is
  # why the probe walks the whole list instead of leaving on the first healthy scene. A scene with no
  # deployed file is skipped by its own condition, so a name may be listed before the file lands.
  # `toast`, `launcher` and `notifications` are left out on purpose — they are on demand, and a hung
  # one is noticed by the thing that asked for it.
  pleamarHealthScenes = [
    "bar"
    "panels"
  ];
  healthScenes = lib.concatStringsSep " " (map (s: "\"${s}\"") pleamarHealthScenes);

  # Login-phase contract shared with the login layer: while the marker exists the
  # lock scene owns the screen and no session scene may start. systemd re-evaluates
  # the condition when the marker is removed after the password, so the units still
  # come up with hyprland-session.target.
  loginPhaseGuard = "!%t/pleamar-login/login-phase";

  # ── Deployment ────────────────────────────────────────────────────────────
  # Live repo links (config.lib.neg.live): editing files/pleamar takes effect in
  # the deployed tree without a rebuild, exactly the way the old shell's tree was
  # deployed.
  pleamarShellsLive = config.lib.neg.live "files/pleamar/shells";
  pleamarLibLive = config.lib.neg.live "files/pleamar/lib";

  # Top-level entries of each source dir, discovered at eval time: a new scene
  # directory or library file gets its link without touching this module.
  pleamarShellEntries = builtins.readDir (config.lib.neg.path "files/pleamar/shells");
  pleamarLibEntries = builtins.readDir (config.lib.neg.path "files/pleamar/lib");
  pleamarShellNames = builtins.filter (n: pleamarShellEntries.${n} == "directory") (
    builtins.attrNames pleamarShellEntries
  );
  pleamarLibNames = builtins.attrNames pleamarLibEntries;

  # ~/.config/pleamar/autostart — the manual/foreign-session entry point
  # (`exec-once = pleamar --autostart`). Pleamar runs each line through `sh -c`,
  # so $HOME expands; comment lines and `wm:` lines are skipped by its parser.
  pleamarAutostart = pkgs.writeText "pleamar-autostart" ''
    # Generated by modules/user/nix-maid/gui/pleamar.nix — do not edit.
    # One shell per line; `pleamar --autostart` starts each via sh and exits.
    ${lib.concatMapStringsSep "\n" (
      scene: "pleamar --scene \"$HOME/.config/pleamar/shells/${scene}/${scene}.plm\" --no-hud"
    ) pleamarScenes}
  '';

  # Helper workers a scene spawns by name (`permissions { run: "pleamar-sysmon" }`):
  # nix-maid links them into ~/.local/bin so `spawn("pleamar-sysmon", …)` resolves
  # (the unit PATH already puts %h/.local/bin first). The names are the contract
  # INTERFACES.md §7 fixes. All workers are the Rust crates
  # packages/pleamar-sysmon/-weather/-calendar/-journal/-kbdlayout.
  pleamarHelperLinks = {
    ".local/bin/pleamar-sysmon" = {
      source = lib.getExe pkgs.neg.pleamar-sysmon;
    };
    ".local/bin/pleamar-weather" = {
      source = lib.getExe pkgs.neg.pleamar-weather;
    };
    ".local/bin/pleamar-journal" = {
      source = lib.getExe pkgs.neg.pleamar-journal;
    };
    ".local/bin/pleamar-calendar" = {
      source = lib.getExe pkgs.neg.pleamar-calendar;
    };
    ".local/bin/pleamar-kbdlayout" = {
      source = lib.getExe pkgs.neg.pleamar-kbdlayout;
    };
  };

  # The wallpaper deck's own commands (features.gui.wallpaperPicker): the colours of a wallpaper
  # folder, applying one, and the `pleamar-picker` the compositor bind calls. They are not workers:
  # the scene runs them to completion, and `pleamar-picker current` is what the theme pipeline's
  # producer path already holds.
  pleamarPickerHelperLinks = {
    ".local/bin/pleamar-wallpaper-apply" = {
      source = lib.getExe' pkgs.neg.pleamar-picker "pleamar-wallpaper-apply";
    };
    ".local/bin/pleamar-wallpaper-still" = {
      source = lib.getExe' pkgs.neg.pleamar-picker "pleamar-wallpaper-still";
    };
    ".local/bin/pleamar-picker" = {
      source = lib.getExe' pkgs.neg.pleamar-picker "pleamar-picker";
    };
  };

  # Icons: pleamar's `icon "…"` looks only under ~/.local/share/icons, ~/.icons and
  # /usr/share/icons, in the fixed theme list hicolor, Papirus, Papirus-Dark,
  # Adwaita, breeze, breeze-dark — never index.theme. On NixOS the themes live in
  # the system profile, so the searched names this shell needs are linked here;
  # lib/icons.plm resolves its glyphs in Adwaita, with hicolor as the base.
  pleamarIconLinks =
    neg.mkDirLinks ".local/share/icons" "${pkgs.adwaita-icon-theme}/share/icons" [ "Adwaita" ]
    // neg.mkDirLinks ".local/share/icons" "${pkgs.hicolor-icon-theme}/share/icons" [ "hicolor" ];

  # Theme pipeline: the compiled crate lives in the system closure; the theme
  # directory only carries the seed and its docs, and the generated
  # ~/.config/pleamar/theme.plm is user data, never a Nix-owned file.
  pleamarThemeLinks =
    neg.mkDirLinks ".local/lib/pleamar" "${config.lib.neg.live "files/pleamar/scripts"}"
      [ "theme" ];

  # `pleamar-wallpaper-palettes`, the theme pipeline and the picker commands are
  # Rust packages now; no picker helper is a shell script any more.
  pleamarPaletteBin = {
    ".local/bin/pleamar-wallpaper-palettes".source = lib.getExe pkgs.neg.wallpaper-palettes;
    # Manual runs (and the theming workflow) use the same compiled pipeline.
    ".local/bin/pleamar-theme".source = lib.getExe pkgs.neg.pleamar-theme;
    # The second binary of the same package: hand-written themes (`list`,
    # `apply`, `show`) write the same theme.plm the pipeline does.
    ".local/bin/pleamar-themes".source = lib.getExe' pkgs.neg.pleamar-theme "pleamar-themes";
  };

  # The themes the shell ships: `files/pleamar/themes/*.toml` linked into
  # ~/.config/pleamar/themes, where `pleamar-themes list` finds them. A theme the
  # user writes there under a name of their own is not touched; the ones listed
  # here are Nix-owned and a local edit to one is replaced on activation.
  pleamarThemeFiles =
    neg.mkDirLinks ".config/pleamar/themes" (config.lib.neg.live "files/pleamar/themes")
      [
        "amber.toml"
        "graphite.toml"
        "paper.toml"
        "nord.toml"
        "gruvbox.toml"
        "tokyo.toml"
        "sakura.toml"
        "forest.toml"
        "mono.toml"
        "sand.toml"
      ];

  pleamarHomeFiles =
    neg.mkDirLinks ".config/pleamar/shells" pleamarShellsLive pleamarShellNames
    // neg.mkDirLinks ".config/pleamar/lib" pleamarLibLive pleamarLibNames
    // pleamarHelperLinks
    // lib.optionalAttrs pickerEnabled pleamarPickerHelperLinks
    // pleamarIconLinks
    // pleamarThemeLinks
    // pleamarThemeFiles
    // pleamarPaletteBin
    // {
      ".config/pleamar/autostart" = {
        source = pleamarAutostart;
      };
    };

  # ── Units ─────────────────────────────────────────────────────────────────
  # One unit per scene: crash isolation, per-scene caps and restart, so a
  # wedged notification scene cannot take the bar down. The scene-file
  # condition keeps a scene that is listed here but not linked yet from
  # failing the unit — it is skipped instead.
  pleamarSceneUnit =
    scene:
    systemdUser.mkUserService {
      description = "Pleamar scene '${scene}'";
      presets = [ "restartOnFailure" ];
      after = [
        "graphical-session-pre.target"
        "maid-activation.service"
        "pipewire.service"
      ];
      wants = [
        "graphical-session-pre.target"
        "maid-activation.service"
        "pipewire.service"
      ];
      partOf = [ "hyprland-session.target" ];
      wantedBy = [ "hyprland-session.target" ];
      unitConfig = {
        # A scene crash loop must give up: five starts in 30 s, then stay down
        # until the session is restarted (the policy the old shell's unit had).
        StartLimitIntervalSec = 30;
        StartLimitBurst = 5;
        ConditionPathExists = [
          loginPhaseGuard
          "%h/.config/pleamar/shells/${scene}/${scene}.plm"
        ];
      };
      serviceConfig = {
        # `--stall 0`: pleamar's own default is 600 ms of live-lock after every decision — a
        # debug aid for its decoupled logic thread, and the reason a click in this bar took half
        # a second to show and sometimes did not show at all. The scene's work is microseconds;
        # nothing here needs to prove the renderer survives a blocking logic.
        ExecStart = "${pkgs.pleamar}/bin/pleamar --scene %h/.config/pleamar/shells/${scene}/${scene}.plm --no-hud --stall 0";
        # `on-failure` is not enough for a scene the session cannot lose: when
        # Hyprland restarts it closes its clients, the scene exits 0, and the
        # bar stays gone until somebody starts it by hand. The bar and the
        # always-resident scenes come back from any exit; `panels` keeps the
        # failure-only policy, since it is the one scene that may close itself.
        Restart = if builtins.elem scene pleamarResidentScenes then "always" else "on-failure";
        RestartSec = 5;
        # Starter ceilings (PH0) measured wrong: every scene sat pinned at the
        # 64M MemoryHigh, while the bar alone needs ~73M peak with no cap;
        # the surplus went to swap (notifications swapped 322M), the renderer
        # starved and the health probe timed out. High throttles before Max
        # kills; both bound a runaway, but with room for a real scene.
        MemoryHigh = "256M";
        MemoryMax = "512M";
        CPUQuota = "100%";
        Environment = [
          # ~/.local/bin first: scenes shell out to user helpers that live there
          # (rsmetrx, …), then the system profile.
          "PATH=%h/.local/bin:/run/current-system/sw/bin:\${PATH}"
          # No cursor variables: the shell carries no cursor patch either, so a scene asks for the
          # shape its own zones declare (arrow, hand, text) and gives the default back on leaving —
          # upstream behaviour, nothing of ours in the pointer's way. `PLEAMAR_NO_CURSOR_SHAPES`
          # never existed upstream; the local patch that replaced it is gone too (2026-11-01, on
          # the owner's call: the pointer trouble was neru's stale evdev proxy, not this shell).
        ];
      };
    };

  pleamarUnits = lib.listToAttrs (
    map (scene: {
      name = "pleamar-${scene}";
      value = pleamarSceneUnit scene;
    }) pleamarScenes
  );

  # Scenes that must not come up with the session. `lock` is born locked
  # (`fact locked = true` in shells/lock/lock.plm), so a unit wanted by
  # hyprland-session.target would put the pleamar lock screen in front of every
  # session. The login phase runs the same scene by hand instead, from
  # `pleamar-login-layer` (modules/user/session/greetd/login-layer.sh, started by
  # the login branch of files/gui/hypr/hyprland.lua), which is the only place that
  # may start it before a password has been accepted. The unit still exists, with
  # the same caps, restart policy and scene condition, so a lock bind or hypridle
  # can start it inside the session:
  #
  #     systemctl --user start pleamar-lock.service     # lock now
  #     pleamar --say lock "fact locked false"          # unlock (PAM first)
  #
  # Both halves are behind PH3-L's PAM matrix, a human gate (superplan:
  # `human-gate="yes"`): the owner runs it at a logout, never a test. A bad login
  # screen is undone with the previous generation (`nixos-rebuild --rollback`), not
  # with a config switch: the Quickshell layer it replaced was deleted on 2026-11-02,
  # so git history is the only way back to it.
  pleamarOnDemandUnits = {
    pleamar-lock = (pleamarSceneUnit "lock") // {
      wantedBy = [ ];
      partOf = [ ];
    };
    # The overlay scene: the shared dismissal catcher, the semaphore relay and the idle inhibitor
    # (`systemd-inhibit` while `fact inhibit` holds). Nothing it does is worth a resident process —
    # its only verbs are IPC (`pleamar --say overlay "fact inhibit true"`), which is the module's own
    # argument against autostarting `overview` — but it should be startable when it is wanted:
    #   systemctl --user start pleamar-overlay.service
    #   pleamar --say overlay "fact inhibit true"     # keep the session awake
    #   pleamar --say overlay "fact inhibit false"    # let it idle again
    # Its surface is `open: active`, so an idle overlay maps nothing at all.
    pleamar-overlay = (pleamarSceneUnit "overlay") // {
      wantedBy = [ ];
      partOf = [ ];
    };
  };

  # The wallpaper deck (features.gui.wallpaperPicker): opened by its bind
  # (`~/.local/bin/pleamar-picker`, M4+C+w) and never wanted by the session — a deck nobody asked
  # for costs a process per monitor, and its first frame is a folder to read. The on-demand shape
  # the lock and the overlay use:
  #
  #     systemctl --user start pleamar-picker.service   # or: pleamar-picker toggle
  #     pleamar --say picker "emit open_picker"         # what the command line does after that
  #
  # No `Restart=always`: a deck that is done exits 0 (Escape, or a card chosen) and stays closed
  # until the bind asks again, which is what `Restart=on-failure` from `pleamarSceneUnit` gives.
  pleamarPickerUnits = lib.optionalAttrs pickerEnabled {
    pleamar-picker = (pleamarSceneUnit "picker") // {
      wantedBy = [ ];
      partOf = [ ];
    };
  };

  # Hang watchdog: `Restart=on-failure` covers a scene that *exits*; a scene
  # that keeps running with dead logic is invisible to systemd. One
  # `--say <scene> describe` round-trip every 2 minutes notices it; the probe
  # only restarts after TWO misses in a row (15 s timeout — the old 5 s one
  # and a single miss restarted the bar 74 times in one day).
  pleamarHealth = pkgs.writeShellScript "pleamar-health" ''
    set -uo pipefail

    for scene in ${healthScenes}; do
      unit="pleamar-$scene.service"
      fails_file="''${XDG_RUNTIME_DIR:-/tmp}/pleamar-health-$scene.fails"

      # A stopped or crashed scene is not this probe's business: restartOnFailure
      # owns that path, and the login-phase condition keeps scenes down on
      # purpose behind the login screen.
      [ "$(systemctl --user is-active "$unit" 2>/dev/null || true)" = "active" ] || continue

      if timeout 15 pleamar --say "$scene" describe > /dev/null 2>&1; then
        rm -f "$fails_file" 2>/dev/null || true
        # `continue`, not `exit 0`: this probe watches every scene in `healthScenes`, and leaving
        # the script on the first healthy one meant a wedged `panels` was never looked at while
        # the bar answered — which is the normal case.
        continue
      fi

      # Only an instance that has been up for a while can be called wedged: a
      # scene that is still starting (or one that just restarted) answers late.
      active_us="$(systemctl --user show -p ActiveEnterTimestampMonotonic --value "$unit" 2>/dev/null || true)"
      active_us="''${active_us:-0}"
      case "$active_us" in
        *[!0-9]*) continue ;;
      esac
      [ "$active_us" -gt 0 ] || continue

      uptime_s="$(cut -d. -f1 /proc/uptime)"
      active_s=$((active_us / 1000000))
      [ $((uptime_s - active_s)) -ge 90 ] || continue

      # Consecutive misses: one slow probe (a busy scene) must not restart it.
      fails=0
      if [ -r "$fails_file" ]; then
        fails="$(cat "$fails_file" 2>/dev/null || echo 0)"
      fi
      case "$fails" in *[!0-9]* | "") fails=0 ;; esac
      fails=$((fails + 1))
      printf '%s' "$fails" > "$fails_file" 2>/dev/null || true
      [ "$fails" -ge 2 ] || continue
      rm -f "$fails_file" 2>/dev/null || true

      systemctl --user restart "$unit"
    done
  '';

  # Remove STALE nix-maid symlinks before activation redeploys them: a link
  # left behind by a renamed or removed scene/library must not dangle. Only
  # broken links go — deleting every link (the first version) pulled live
  # /etc/nixos targets out from under scenes that (re)started inside the
  # cleanup→activation window (33 "cannot read … .plm" crashes in one day).
  # Writable runtime state (~/.config/pleamar) is still not ours to remove.
  pleamarCleanup = {
    description = "Remove old pleamar symlinks before nix-maid activation";
    before = [ "maid-activation.service" ];
    wantedBy = [ "maid-activation.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "pleamar-cleanup-symlink" ''
        dst="$HOME/.config/pleamar"
        if [ -L "$dst" ]; then
          rm -f "$dst" 2>/dev/null || true
        elif [ -d "$dst" ]; then
          for sub in shells lib; do
            [ -d "$dst/$sub" ] && find "$dst/$sub" -maxdepth 1 -type l -xtype l -delete 2>/dev/null || true
          done
          [ -L "$dst/autostart" ] && [ ! -e "$dst/autostart" ] && rm -f "$dst/autostart" 2>/dev/null || true
        fi
        # Helper links live in ~/.local/bin: drop the broken ones pointing into this repo.
        find "$HOME/.local/bin" -maxdepth 1 -type l -lname '*files/pleamar*' -xtype l -delete 2>/dev/null || true
        # The scenes import ~/.config/pleamar/art.plm (`bar.plm`, `panels.plm`), and only the bar's
        # logic writes it, after a cover is sampled. A fresh HOME has no bar yet, and a missing
        # import is a compile error, not a fallback. Seed the repository default first; a generated
        # file is kept (the bar rewrites it). This runs before maid-activation, so before any scene.
        art="$HOME/.config/pleamar/art.plm"
        if [ ! -e "$art" ]; then
          install -Dm644 ${config.lib.neg.live "files/pleamar/art.plm"} "$art" 2>/dev/null || true
        fi
        # The static tree the links point at is NOT removed here: pruning it before
        # activation is what left every deployed scene dangling for the length of a copy —
        # 2 "cannot read … .plm" errors per switch (bar and notifications, 18:06 today).
        # `pleamarPrune` does it after activation instead.
      '';
    };
  };

  # Prune the static copy AFTER activation, which is where the old `rm -rf` belonged.
  #
  # Every deployed scene is a link into ~/.local/state/nix-maid/static/.config/pleamar, so
  # deleting that tree before activation left each link dangling for as long as the copy took:
  # that is the "cannot read … .plm" pair per switch (bar and notifications, 18:06 today). The
  # purpose — a scene or library removed from `files/pleamar/` must not leave a stale copy — is
  # served just as well afterwards, when everything live already resolves and the prune can only
  # remove what no link names any more.
  pleamarPrune = {
    description = "Prune pleamar's static copy after activation";
    after = [ "maid-activation.service" ];
    wantedBy = [ "maid-activation.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "pleamar-prune-static" ''
        static="$HOME/.local/state/nix-maid/static/.config/pleamar"
        dst="$HOME/.config/pleamar"
        [ -d "$static" ] || exit 0
        for sub in shells lib; do
          [ -d "$static/$sub" ] || continue
          for entry in "$static/$sub"/*; do
            [ -e "$entry" ] || continue
            name="''${entry##*/}"
            [ -e "$dst/$sub/$name" ] || rm -rf "$entry" 2>/dev/null || true
          done
        done
        # A `.path` unit whose file a switch replaced is stopped and does not come back on its own:
        # `WantedBy=graphical-session.target` only pulls it in when that target *starts*, and it was
        # already up. On 2026-11-02 `pleamar-theme.path` sat dead from 02:36 to 06:00 that way, so a
        # wallpaper change ran nothing at all. Starting it again is idempotent.
        systemctl --user start pleamar-theme.path > /dev/null 2>&1 || true
      '';
    };
  };

  # Seed ~/.config/pleamar/theme.plm once from the default, then let the compiled
  # pipeline rewrite it from the wallpaper. A failing run leaves the previous
  # file intact. After a write the palette is handed to the scenes that draw it
  # live (`palette.json` in each one's data folder, `pleamar-themes push`), so a
  # converted scene re-themes without a reload; a failing push is not a failing
  # theme run, and the scenes catch up on their next start or push.
  pleamarThemeRun = pkgs.writeShellScript "pleamar-theme" ''
    set -eu
    theme_dir="$HOME/.local/lib/pleamar/theme"
    dst="$HOME/.config/pleamar/theme.plm"
    if [ ! -e "$dst" ]; then
      install -Dm644 "$theme_dir/theme.default.plm" "$dst"
    fi
    ${lib.getExe pkgs.neg.pleamar-theme}
    ${lib.getExe' pkgs.neg.pleamar-theme "pleamar-themes"} push || true
  '';
in
lib.mkIf pleamarEnabled (
  lib.mkMerge [
    {
      # The runtime itself: `pleamar --check`, `--say`, `--report` and manual
      # scene runs need it on PATH while the feature is on.
      environment.systemPackages = [
        pkgs.pleamar # Wayland desktop shell runtime (bars/launchers/notifications as scenes)
        pkgs.neg.pleamar-harness # dev harnesses: PNG matrix, describe snapshots, cgroup budgets
      ];

      # The lock scene checks the password through the PAM service the engine names in its
      # own source — `/etc/pam.d/pleamar`, `sys.ask("auth.check", …)` — and NixOS writes that
      # file only for a service somebody declared. Without this the lock has nothing to ask:
      # `auth.check` fails before it ever reaches a password.
      #
      # `unixAuth` is that password; `fprintAuth` is `control = "sufficient"` in nixpkgs, so
      # the reader is tried first and the password decides when there is no finger — the order
      # of the reference's `greeter/lock/pam/fprint.conf`. No reader is plugged into this host,
      # so the finger half falls through every time (same story as the Caps Lock LED, which the
      # kanata remap `caps → lctl` never lights).
      security.pam.services.pleamar = {
        unixAuth = true;
        fprintAuth = true;
      };

      systemd.user.services =
        pleamarUnits
        // pleamarOnDemandUnits
        // pleamarPickerUnits
        // {
          pleamar-health = systemdUser.mkUserService {
            description = "Restart the pleamar scene when it stops answering";
            presets = [ "oneshot" ];
            # User units start with a minimal PATH: the probe needs its own CLI
            # plus timeout/systemctl/cut.
            path = [
              pkgs.coreutils # timeout and cut, used by the probe
              pkgs.systemd # systemctl --user: the liveness check and the restart
              pkgs.pleamar # the scene's own CLI for `pleamar --say`
            ];
            serviceConfig = {
              ExecStart = pleamarHealth;
            };
          };
          pleamar-cleanup-symlink = pleamarCleanup;
          pleamar-prune-static = pleamarPrune;
          pleamar-theme = systemdUser.mkUserService {
            description = "Write ~/.config/pleamar/theme.plm from the current wallpaper";
            presets = [ "oneshot" ];
            after = [
              "maid-activation.service"
              "wl-state-sync.service"
            ];
            wants = [ "maid-activation.service" ];
            wantedBy = [ "graphical-session.target" ];
            # Runs on every wallpaper change: bursts are normal, not a failure.
            unitConfig.StartLimitIntervalSec = 0;
            # The compiled pipeline shells out to imagemagick and jq.
            path = [
              pkgs.coreutils # install/text tools used by the wrapper
              pkgs.imagemagick # samples the wallpaper's colours
              pkgs.jq # JSON reads in the pipeline
            ];
            serviceConfig = {
              ExecStart = pleamarThemeRun;
            };
          };
        };

      systemd.user.timers.pleamar-health = {
        description = "Timer: pleamar scene hang watchdog";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "2m";
        };
      };

      systemd.user.paths.pleamar-theme = {
        description = "Run the pleamar theme pipeline when the wallpaper changes";
        wantedBy = [ "graphical-session.target" ];
        pathConfig = {
          # The producer path the theme pipeline reads (INTERFACES.md §1.2). The legacy
          # `quickshell-wallpaper-path` it used to watch beside it went with the shell
          # that introduced it (2026-11-02) and its last writer (2026-11-03).
          PathModified = [
            "%h/.cache/pleamar/wallpaper-path"
          ];
          Unit = "pleamar-theme.service";
        };
      };
    }
    (neg.mkHomeFiles pleamarHomeFiles)
  ]
)
