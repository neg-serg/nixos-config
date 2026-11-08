##
# Module: dev/craft-anything
# Purpose: Craft Anything — a reverse-engineering workbench that reads an
# executable, a file, a website or a game, keeps an evidence ledger and drives
# a coding agent to rebuild it (features.dev.craftAnything).
#
# Upstream: https://github.com/storytold/craft-anything (MIT OR Apache-2.0).
# One workspace, three front ends: the egui desktop app, `craft-anything-cli`
# (every tool, the MCP server, `doctor`) and a wasm web viewer. The package is
# `packages/craft-anything`; see its header for what is built.
#
# The app is a large Rust tree (wgpu, egui, ~800 crates) and nothing on this
# host starts it on its own: it is a manual tool. Both binaries therefore go
# through lib/on-demand-app.nix — the first call builds `.#craft-anything`,
# registers a GC root under `~/.local/state/nix-apps` and execs the binary, so
# the system generation carries two small wrappers and none of the 300-tool
# engine. The package's own desktop file and icons stay inside that root; the
# desktop entry below is what the launcher sees.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "dev.craftAnything";
  onDemand = config.lib.neg.onDemand pkgs;
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = [
      (onDemand {
        name = "craft-anything";
        attr = "craft-anything";
      }) # workbench GUI: study a target, keep the evidence, rebuild it
      (onDemand {
        name = "craft-anything-cli";
        attr = "craft-anything";
        binary = "craft-anything-cli";
      }) # the same tools on the command line, plus `mcp` and `doctor`
      (pkgs.makeDesktopItem {
        name = "ai.storyteller.craft-anything";
        desktopName = "Craft Anything";
        genericName = "Software Explorer";
        comment = "Find out how any software works, then craft your own";
        exec = "craft-anything %F";
        icon = "ai.storyteller.craft-anything";
        categories = [
          "Development"
          "Debugger"
        ];
        # eframe sets the Wayland app_id / X11 class to the value upstream's
        # packaging/linux desktop file declares, so the compositor groups the
        # window under this entry.
        startupWMClass = "ai.storyteller.craft-anything";
      })
    ];
  };
}
