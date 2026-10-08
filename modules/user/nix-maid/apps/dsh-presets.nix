# Agent-preset declarations for the terminal dsh profile (dsh 0.2.0+).
#
# Until 0.1.6 a preset was a directory `$DSH_HOME/.agent-presets/<id>/` holding
# `preset.yml` (display metadata) and `agent.cordis.yml` (the plugin entry
# list); dsh-fast.nix and dsh-liangshen-fork.nix synced the repo copies into
# that root and the harness scanned it. Since 0.1.7 the registry composes
# presets from *declaration rows* (`@deepseek-ai/dsh-agent-preset` carried by a
# bundle patch layer) and the directory is dead — nothing reads it. The shipped
# presets live as `presets/<id>.patch.yml` inside the dsh-web-app bundle, which
# the tui profile does not mount; the dsh-TUI bundle only wires the registry
# itself (default `standard`). So this deployment declares the two presets it
# uses, as rows in the profile patch layer written by dsh-tui-preset-patch.py
# from the data below.
#
# `plugins` points at the same `agent.cordis.yml` files the modules used to
# ship into `.agent-presets`: its entry list becomes the declaration's
# `plugins` verbatim, which is exactly what upstream's migration guide asks for
# ("plugins from agent.cordis.yml verbatim; check each plugin name against
# cordis-composition-reference because packages renamed since the preset was
# written fail at activation"). The 0.2.0-rc.2 check found one rename:
# `@deepseek-ai/dsh-workflow-worker-thread` -> `@deepseek-ai/dsh-workflow-ptc`,
# applied in dsh-liangshen-fork/agent.cordis.yml.
#
# `sidecars` are files the declaration references by a *relative* path (anchored
# beside the patch file, i.e. the profile directory): the caretaker copies them
# next to the patch layer. `order` is the roster position; `description` is
# rendered by the picker and duplicates the preset.yml text (keep both in sync).
# Data module, not a NixOS module: apps/default.nix excludes it from
# importDir and dsh-tui.nix imports it with { pkgs }.
{ pkgs }:
let
  presets = [
    {
      id = "neg";
      name = "neg";
      order = 5;
      description = "Пресет neg — форк LiangShen (anchored-standard), поддерживаемый в /etc/nixos: фаза 1 — минимальная поверхность (bash + str_replace_editor, персона с дисциплиной мышления), после якоря — промоушен в Code Mode (PTC) с полным каталогом инструментов.";
      plugins = ./dsh-liangshen-fork/agent.cordis.yml;
      # Sidecars are { src; name; }: a store path's file name carries the hash
      # prefix, so the caretaker cannot derive the destination from it.
      sidecars = [
        {
          src = ./dsh-liangshen-fork/tool-bootstrap.mjs;
          name = "tool-bootstrap.mjs";
        }
      ];
    }
    {
      id = "fast";
      name = "Fast — лёгкий";
      order = 4;
      description = "Лёгкий быстрый режим: короткая персона без лишних секций, 4 инструмента (bash, редактор, веб-поиск, вопросы) — мало токенов, без долгих размышлений. Переключение: /fast (сюда), /smart (обратно на neg).";
      plugins = ./dsh-fast/agent.cordis.yml;
      sidecars = [ ];
    }
  ];

  # The plugin a declaration row names, and the registry row whose `default`
  # the profile layer overrides (the TUI's own row id — the shipped web-app row
  # is `agent-preset-registry`, which this profile has no reason to mount).
  declarationPlugin = "@deepseek-ai/dsh-agent-preset";
  registryRow = "dsh-tui-agent-preset-registry";

  # JSON handed to the patch writer. The paths stay path literals inside the
  # JSON (writeText keeps them in the caretaker's closure), and the writer
  # re-indents each `plugins` file under its declaration's config.
  json = pkgs.writeText "dsh-agent-presets.json" (
    builtins.toJSON {
      inherit presets declarationPlugin registryRow;
      defaultPreset = "neg";
    }
  );
in
{
  inherit
    presets
    json
    declarationPlugin
    registryRow
    ;
}
