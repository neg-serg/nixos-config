{
  lib,
  config,
  pkgs,
  self,
  ...
}:
let
  cfg = config.flakePreflight;
  toStr = builtins.toString;
in
{
  options.flakePreflight = {
    enable = lib.mkEnableOption "Run 'nix flake check' during activation (best-effort).";

    timeoutSec = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
      description = "Maximum time to spend on flake checks (seconds).";
      example = 90;
    };

    offline = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run with --offline to avoid network access during checks.";
    };

    niceLevel = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "CPU niceness for the check process (nice -n).";
    };

    ioniceClass = lib.mkOption {
      type = lib.types.int;
      default = 2; # best-effort
      description = "I/O scheduling class for the check process (ionice -c).";
    };

    ionicePriority = lib.mkOption {
      type = lib.types.int;
      default = 7; # lowest priority within the class
      description = "I/O priority for the check process (ionice -n).";
    };

    extraArgs = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "Extra arguments to pass to 'nix flake check'.";
      example = [
        "--show-trace"
        "--print-build-logs"
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    system.activationScripts.flakePreflight.text = ''
      echo -e "\e[1mFlake checks (best effort):\e[0m"
      ${pkgs.coreutils}/bin/timeout ${toStr cfg.timeoutSec}s \ # GNU Core Utilities
        ${pkgs.util-linux}/bin/ionice -c ${toStr cfg.ioniceClass} -n ${toStr cfg.ionicePriority} \ # Set of system utilities for Linux
        ${pkgs.coreutils}/bin/nice -n ${toStr cfg.niceLevel} \ # GNU Core Utilities
        ${config.nix.package}/bin/nix \
          --experimental-features nix-command flakes \
          --accept-flake-config \
          ${lib.optionalString cfg.offline "--offline"} \
          flake check ${self} ${lib.concatStringsSep " " cfg.extraArgs} \
        || echo "flake check exited with status $?"
      echo
    '';
  };
}
