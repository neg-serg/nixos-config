##
# Module: dev/java
# Purpose: Java/JVM development tooling (Apache Maven; it brings its own JDK)
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
    environment.systemPackages = lib.optionals cfg.maven [ pkgs.maven ];
  };
}
