{pkgs, ...}: {
  environment.systemPackages = [pkgs.asciinema]; # Terminal session recorder

  # Terminal toolchain packages are provided system-wide via modules/cli/pkgs.nix
  # and modules/user/session/pkgs.nix.
}
