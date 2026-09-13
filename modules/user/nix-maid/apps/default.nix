{
  lib,
  ...
}:
let
  entries = builtins.readDir ./.;
in
{
  # Data directories here are not modules: dsh-tui-ru-assets/ (the TUI patcher,
  # translation map and themes), dsh-liangshen-fork/ and dsh-fast/ (agent
  # presets), and the per-plugin bundles the TUI profile seeds through
  # dsh-tui-ru.nix (dsh-advisor/, dsh-hashline/, …). The web-profile plugin
  # caretakers were removed in 2026-09 with the web GUI.
  imports =
    builtins.attrNames entries
    |> builtins.filter (
      n:
      n != "default.nix"
      && n != "dsh-tui-ru-assets"
      && n != "dsh-liangshen-fork"
      && n != "dsh-fast"
      && n != "dsh-mode"
      && n != "dsh-session-tools"
      && n != "dsh-agent-usage-reminder"
      && n != "dsh-compaction-todo-preserver"
      && n != "dsh-rules-injector"
      && n != "dsh-category-skill-reminder"
      && n != "dsh-hashline"
      && n != "dsh-debug"
      && n != "dsh-secrets-masker"
      && n != "dsh-eval"
      && n != "dsh-ttsr"
      && n != "dsh-hub"
      && n != "dsh-ast-grep"
      && n != "dsh-checkpoint"
      && n != "dsh-read-tags"
      && n != "dsh-advisor"
      && n != "dsh-desktop"
      && n != "dsh-json-error-recovery"
      && n != "dsh-notepad-write-guard"
      && n != "dsh-keyword-detector"
      && n != "dsh-plan-format-validator"
      && n != "dsh-task-resume-info"
      && n != "dsh-delegate-task-retry"
      && n != "dsh-plugin-recall"
      && n != "dsh-plugin-vetting"
      && n != "dsh-worktree"
      && n != "dsh-diff"
      && n != "dsh-statusline"
      && n != "dsh-notify-input"
      && (entries.${n} == "directory" || lib.hasSuffix ".nix" n)
    )
    |> builtins.map (n: ./. + "/${n}");
}
