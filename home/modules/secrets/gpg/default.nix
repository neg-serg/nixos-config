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
