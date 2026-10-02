{
  hyprglassApply,
  hyprglassPath,
  ...
}:
{
  systemdServices = {
    # Watchdog for the glass settings: the plugin drops its config when the
    # compositor re-initialises it, and nothing else reports that. The timer in
    # sys/user-services.nix runs this every 10 s; it checks first, so a healthy
    # session costs nine `hyprctl getoption` reads and no writes.
    hyprglass-watch = {
      description = "Re-apply hyprglass settings if they drifted";
      serviceConfig = {
        Type = "oneshot";
        # The same PATH as the apply below — see hyprglassPath. This unit was
        # without one, so jq was missing and every tick ended in "jq is missing".
        Environment = [ "PATH=${hyprglassPath}" ];
        ExecStart = "${hyprglassApply}/bin/hyprglass-apply --watch";
      };
    };

    # Triggered by hyprglass-config.path when the glass config is (re)deployed
    # or the panel writes overrides.
    hyprglass-apply = {
      description = "Push hyprglass settings into the running session";
      serviceConfig = {
        Type = "oneshot";
        # Without this the script could not read the panel's JSON (jq) and
        # silently pushed only the defaults, so the panel's values never landed.
        Environment = [ "PATH=${hyprglassPath}" ];
        ExecStart = "${hyprglassApply}/bin/hyprglass-apply";
      };
      unitConfig = {
        # A slider drag rewrites the override file several times per second, and
        # the default StartLimitBurst (5 in 10 s) turned that into
        # "start-limit-hit": the applies stopped and the units went to failed.
        StartLimitIntervalSec = 0;
      };
    };
  };
}
