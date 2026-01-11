##
# Module: system/profiles/security
# Purpose: Security-oriented feature toggle(s).
# Key options: cfg = config.profiles.security.enable
# Dependencies: Consumed by kernel params (e.g., page_poison).
{ lib, ... }:
# Security-focused toggles to harden the system at a small performance cost.
let
  inherit (lib) mkEnableOption;
in
{
  options.profiles.security = {
    enable = mkEnableOption "Enable security-oriented kernel tweaks (e.g., page poisoning).";
  };
}
