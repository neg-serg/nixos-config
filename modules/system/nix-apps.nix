##
# Module: system/nix-apps
# Purpose: `nix-apps` — list/status/update/clean for the on-demand GC roots.
#
# The on-demand pattern (lib/on-demand-app.nix) keeps heavy apps out of the
# system closure: a launcher builds the flake attr on first use and pins the
# result to a GC root under ~/.local/state/nix-apps/<name> (per user) or
# /var/lib/nix-apps/<name> (system services, see modules/llm/default.nix).
# The root is a *pin*, not a cache: it keeps that exact store path alive until
# `nix-apps update` re-points it or `nix-apps clean` removes it.
#
# Why a separate tool instead of the launchers alone: a launcher only builds
# when the root is missing. After `just update` the root still points at the
# old revision, and only `nix-apps update` refreshes it without waiting for the
# app to be invoked. `nix-apps status` is the drift check — the pinned store
# path vs what the current flake would build.
#
# Typical maintenance:
#
#     nix-apps status              # what went stale after just update
#     nix-apps seed                # after a switch: pin every launcher on PATH
#                                  # so the apps work offline (roots survive GC)
#     nix-apps update              # re-point every managed root
#     nix-apps update vivaldi      # ... or one name
#     nix-apps clean renoise       # drop the pin; the path survives until GC
#
# Adding an app: expose a flake attr (packages/flake/custom-packages.nix) and
# wrap it through lib/on-demand-app.nix; the CLI discovers it by root name. Where
# the attr name differs from the root name, add the pair to map_attr() in
# nix-apps.sh (docling → docling-env, searx → searxng today).
#
# Root names that have no flake attr (vivaldi, telegram-desktop, xray, ...) are
# materialised by their own ensure scripts; `status` reports them as `external`
# and `update` skips them on purpose — their module owns the refresh.
{
  pkgs,
  lib,
  config,
  ...
}:
{
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "nix-apps";
      runtimeInputs = [
        config.nix.package # flake evaluation and nix-store --add-root
        pkgs.coreutils # readlink, rm, head
      ];
      # The file keeps its own shebang so shellcheck can lint it standalone;
      # writeShellApplication adds one, so drop the duplicate here.
      text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./nix-apps.sh);
    })
  ];

  # Shared base for system-service roots (ollama, searx): the ensure oneshots
  # run as the main user and must be able to add roots there.
  systemd.tmpfiles.rules = [
    "d /var/lib/nix-apps 0755 ${config.lib.neg.mainUser} ${config.lib.neg.mainUser} -"
  ];
}
