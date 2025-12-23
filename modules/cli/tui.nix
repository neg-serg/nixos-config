{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.gum # TUIs for shell prompts/menus
    pkgs.peaclock # animated TUI clock (used in panels)
  ];
}
