{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.asciinema ]; # Terminal session recorder

}
