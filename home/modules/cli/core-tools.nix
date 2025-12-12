_: {
  # fd, ripgrep, direnv, shell helpers (nix-your-shell), posh toggle
  programs = {
    fd = {
      enable = true;
      ignores = [".git/"];
    };
    ripgrep = {
      enable = true;
      arguments = [
        "--no-heading"
        "--smart-case"
        "--follow"
        "--hidden"
        "--glob=!.git/"
        "--glob=!node_modules/"
        "--glob=!yarn.lock"
        "--glob=!package-lock.json"
        "--glob=!.yarn/"
        "--glob=!_build/"
        "--glob=!tags"
        "--glob=!.pub-cache"
      ];
    };
    direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableZshIntegration = true;
      enableBashIntegration = false;
    };
    oh-my-posh = {
      # Disabled: oh-my-posh is managed by system wrappers in modules/system/wrappers.nix
      # Having it enabled here causes conflicts with the wrapper's runtime initialization
      enable = false;
    };
    nix-your-shell.enable = true;
  };
}
