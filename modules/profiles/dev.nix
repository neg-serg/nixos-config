{
  lib,
  config,
  ...
}:
lib.mkIf (builtins.elem "dev" (config.features.profiles or [ ])) {
  features = {
    dev = {
      enable = lib.mkDefault true;
      ai.enable = lib.mkDefault true;
      rust.enable = lib.mkDefault true;
      cpp.enable = lib.mkDefault true;
      java.enable = lib.mkDefault true; # enable Java/JVM toolchain (JDK, Maven, PraxisLIVE)
    };
  };
}
