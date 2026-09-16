{
  pkgs,
  ...
}:
{
  # bun runtime for the JS kernel, used by the TUI's dsh-eval plugin. The
  # web-profile caretaker was removed in 2026-09; the TUI profile seeds the
  # plugin itself (dsh-tui.nix).
  environment.systemPackages = [
    pkgs.bun # JS runtime for dsh-eval kernel
  ];
}
