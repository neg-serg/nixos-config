##
# Module: dev/java
# Purpose: Java/JVM development tooling (JDK, Maven, PraxisLIVE IDE)
# Feature flag: features.dev.java.enable
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.features.dev.java;
in
{
  options.features.dev.java = {
    enable = lib.mkEnableOption "Java/JVM development tooling (JDK, Maven, PraxisLIVE)";
    maven = lib.mkEnableOption "Apache Maven build tool" // {
      default = true;
    };
    praxislive = lib.mkEnableOption "PraxisLIVE visual live programming IDE" // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.jdk21
    ]
    ++ lib.optionals cfg.maven [ pkgs.maven ]
    ++ lib.optionals cfg.praxislive [ pkgs.neg.praxislive ];
  };
}
