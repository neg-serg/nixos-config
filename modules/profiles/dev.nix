{
  lib,
  config,
  ...
}:
with lib;
mkIf (builtins.elem "dev" (config.features.profiles or [ ])) {
  features = {
    dev = {
      enable = mkDefault true;
      ai.enable = mkDefault true;
      rust.enable = mkDefault true;
      cpp.enable = mkDefault true;
      haskell.enable = mkDefault true;
      java.enable = mkDefault true; # enable Java/JVM toolchain (JDK, Maven, PraxisLIVE)
      pkgs.iac = mkDefault true; # enable Infrastructure as Code tools (terraform, opentofu)
    };
  };
}
