{pkgs, ...}: {
  home.packages = with pkgs; [
    ytfzf
    chafa
  ];

  home.shellAliases = {
    yt = "ytfzf -t";
  };

  home.sessionVariables = {
    YTFZF_THUMB_BACKEND = "chafa";
  };
}
