{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.abduco # CLI session detach
    pkgs.xxh # SSH wrapper for jumping into remote shells
  ];
}
