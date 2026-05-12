{ pkgs, ... }:
{
  environment.systemPackages = [

    pkgs.par # paragraph reformatter for text (useful for long lines)
    pkgs.choose # cut implementation in rust

  ];
}
