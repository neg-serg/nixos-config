{
  pkgs,
  lib,
  config,
  ...
}: let
  here = ./.;
  entries = builtins.readDir here;
  importables =
    lib.mapAttrsToList (
      name: type: let
        path = here + "/${name}";
      in
        if type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
        then path
        else if type == "directory" && builtins.pathExists (path + "/default.nix")
        then path
        else null
    )
    entries;
  imports = lib.filter (p: p != null) importables;
in {
  inherit imports;

  # Journald: keep logs across reboots to inspect boot output
  services.journald.extraConfig = ''
    Storage=persistent
    # Limit log write bursts to reduce IO spikes
    RateLimitIntervalSec=30s
    RateLimitBurst=2000
    # Keep total journal size reasonable
    SystemMaxFileSize=300M
    SystemMaxFiles=50
  '';

  services.logind.settings.Login = {
    IdleAction = "ignore";
  };

  # Replace ad-hoc nixindex units with native module
  programs.nix-index.enable = true;

  systemd = {
    coredump.enable = true;
    settings = {
      Manager = {
        RebootWatchdogSec = "10s";
      };
    };
    # Ensure the user systemd manager has a sane PATH so TryExec checks
    # for Wayland sessions (e.g., UWSM) do not fail. Include system profile,
    # per-user profile, and the user's state profile where Home Manager installs.
    user.extraConfig = let
      user = config.users.main.name or "neg";
      home = "/home/${user}";
    in ''
      DefaultEnvironment=PATH=/run/current-system/sw/bin:/etc/profiles/per-user/${user}/bin:${home}/.local/state/nix/profile/bin
    '';
    # Favor user responsiveness; de-prioritize nix-daemon slightly
    slices."user.slice".sliceConfig = {
      CPUWeight = 10000;
      IOWeight = 10000;
    };
    services = {
      nix-daemon.serviceConfig = {
        CPUWeight = 200;
        IOWeight = 200;
        LimitNOFILE = 1048576;
      };

      # Silence failing ad-hoc nixindex timer/service; prefer proper modules
      nixindex.enable = lib.mkForce false;

      # Ensure Navidrome waits for the music mount to exist before applying its
      # private mount namespace with BindReadOnlyPaths=/one/music
      navidrome.unitConfig.RequiresMountsFor = ["/one/music"];
    };
    packages = [pkgs.packagekit];
    timers.nixindex.enable = lib.mkForce false;
  };
}
