{
  pkgs,
  config,
  ...
}: {
  programs.asciinema.enable = true;

  # Terminal toolchain packages are provided system-wide via modules/cli/pkgs.nix
  # and modules/user/session/pkgs.nix.
}
