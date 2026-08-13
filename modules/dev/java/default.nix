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
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.jdk21 # Java 21 LTS (current default in nixpkgs)
    ]
    ++ lib.optionals cfg.maven [ pkgs.maven ];
  };
}
