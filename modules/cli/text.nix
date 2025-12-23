{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.choose # yet another cut/awk alternative
    pkgs.enca # detect + reencode text
    pkgs.grex # generate regexes from examples
    pkgs.grc # generic text colorizer
    pkgs.par # paragraph reformatter
    pkgs.sad # simpler sed alternative
    pkgs.sd # intuitive sed alternative
    pkgs.translate-shell # translate CLI used inside menus
  ];
}
