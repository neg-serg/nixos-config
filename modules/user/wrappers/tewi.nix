{ pkgs, ... }:
{
  wrappers.tewi = {
    basePackage = pkgs.neg.tewi;
  };
}
