{ pkgs, ... }:
{
  environment.systemPackages = [

    pkgs.par # paragraph reformatter for text (useful for long lines)

  ];
}
