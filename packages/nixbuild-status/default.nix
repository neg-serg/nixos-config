#
# nixbuild-status — build progress in the bar
# (moved out of the docs tree; keep it in sync with the code it describes)
#
#
# `nixbuild-status` (`packages/nixbuild-status`, Rust, no crate dependencies) answers one question
# without touching Nix: *what is being built right now*. It reads `/proc` for live build processes and
# `/nix/var/log/nix/drvs` for derivation logs — no `nix` subprocess, no daemon, no network, so a panel
# can call it every second.
#
# ## What it detects
#
# A *session* is the topmost matching process, so the `nix build` that `nixos-rebuild` spawns
# internally is part of the rebuild rather than a second entry. Recognised kinds: `nixos-rebuild`,
# `nh os switch`, `nix build`, `nix-build`, `nix-store --realise`, and the activation helper.
#
# States streamed to the bar: `idle`, `evaluating`, `building`, `activating`. With one session its
# fresh derivation logs attach to it; with several, the derivations are reported as one shared list
# (the logs do not say which client started which build).
#
# ## CLI
#
#     $ nixbuild-status                     # one line, nerd-font icons, for a status bar
#     $ nixbuild-status --json              # waybar JSON (the capsule's streaming format)
#     $ nixbuild-status --list              # one line per build: kind target · derivation · time
#     $ nixbuild-status --watch 1 --json    # stay resident, print only on change
#     $ nixbuild-status --format polybar    # plain | ansi | waybar | i3bar | json | polybar | list
#
# Other flags: `--icons nerd|plain|none`, `--no-color`, `--compact` (drop the state word when the icon
# already shows it), `--hide-idle` (empty line instead of the idle line).
#
# ## Where it is wired
#
# - `files/quickshell/Bar/Modules/BuildStatus.qml` — the bar capsule; streams
#   `nixbuild-status --watch 1 --json`, renders an empty label while idle so the capsule only takes
#   bar space during a build.
# - `files/quickshell/Bar/Modules/BuildStatusPopup.qml` — tap-through list, one row per build
#   (command, target, derivation, elapsed).
# - Widget name `nixbuild`; it sits on the right in the default layout
#   (`files/quickshell/Services/WidgetRegistry.qml`, `files/quickshell/Settings/Settings.qml`).
#
# ## Environment hooks
#
# Paths only — for tests and for unusual layouts:
#
# | variable          | default                                  | meaning                                       |
# | ----------------- | ---------------------------------------- | --------------------------------------------- |
# | `NBS_PROC_ROOT`   | `/proc`                                  | where build processes are looked up           |
# | `NBS_LOG_ROOT`    | `/nix/var/log/nix/drvs`                  | derivation logs                               |
# | `NBS_STATE`       | `$XDG_RUNTIME_DIR/nixbuild-status.state` | log offsets and restart counters between runs |
# | `NBS_SYSTEM_LINK` | `/nix/var/nix/profiles/system`           | activation detection                          |
# | `NBS_DEBUG`       | unset                                    | dump the session/log decisions to stderr      |
#
# ## Gotchas
#
# - "Quiet" compilations (no new log output) are not lost: state is carried in `NBS_STATE`, and
#   `NBS_DEBUG` prints the decisions when a build looks invisible.
# - The tool never runs `nix`, so it cannot see a build whose client died — the session simply ends
#   with the last process.

{
  lib,
  rustPlatform,
}:

# nixbuild-status: one-line NixOS build status for status bars (waybar, i3bar,
# polybar). Detection is /proc- plus Nix-log-based: no `nix` subprocess, no
# network, no daemon, and no crate dependencies, so a single run costs a few
# milliseconds and is safe to use as a panel interval command.
rustPlatform.buildRustPackage {
  pname = "nixbuild-status";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "One-line NixOS build status for status bars (waybar/i3bar/polybar)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "nixbuild-status";
  };
}
