{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.par # paragraph reformatter for text (useful for long lines)
    pkgs.grex # generate regular expressions from example strings
  ];
}
