{
  pkgs,
  lib,
  config,
  ...
}:
with {
  pinentryRofi = pkgs.writeShellApplication {
    name = "pinentry-rofi-with-env";
    text = ''
      # Default to the custom askpass theme unless the caller overrides.
      if [ -z "$PINENTRY_ROFI_ARGS" ]; then
        PINENTRY_ROFI_ARGS="-theme askpass"
      fi
      export PINENTRY_ROFI_ARGS
      # Best-effort to provide display/session env when gpg-agent is started early (no GUI vars).
      if [ -z "$WAYLAND_DISPLAY" ] && [ -n "$XDG_RUNTIME_DIR" ]; then
        wayland_socket=""
        wayland_socket=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' -print -quit 2>/dev/null || true)
        if [ -n "$wayland_socket" ]; then
          wayland_base=$(basename "$wayland_socket")
          export WAYLAND_DISPLAY="$wayland_base"
        fi
      fi
      if [ -z "$DISPLAY" ] && [ -n "$WAYLAND_DISPLAY" ]; then
        export DISPLAY=:0
      fi
      if [ -z "$DBUS_SESSION_BUS_ADDRESS" ] && [ -n "$XDG_RUNTIME_DIR" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
      fi
      PATH="$PATH:${pkgs.coreutils}/bin:${config.neg.rofi.package}/bin"
      "${lib.getExe pkgs.pinentry-rofi}" "$@"
    '';
  };
};
with lib;
  mkIf config.features.gpg.enable {
    programs.gpg = {
      enable = true;
      scdaemonSettings = {
        disable-ccid = true;
        pcsc-shared = true;
        reader-port = "Yubico Yubi";
      };
    };
    services.gpg-agent = {
      # Cache passphrases longer and allow long-lived sessions
      defaultCacheTtl = 60480000; # ~700 days (user prefers very infrequent prompts)
      maxCacheTtl = 60480000;
      enableExtraSocket = true;
      enableScDaemon = true;
      enableSshSupport = false;
      enableZshIntegration = true;
      enable = true;
      extraConfig = ''
        pinentry-program ${pinentryRofi}/bin/pinentry-rofi-with-env
        allow-loopback-pinentry
      '';
      verbose = true;
    };
  }
