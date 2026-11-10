{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.lib.neg) mainUser mainGroup homeDir;

  hyprwhsprConfig = pkgs.writeText "hyprwhspr-config.jsonc" (
    builtins.readFile (config.lib.neg.path "files/hyprwhspr/config.jsonc")
  );
in
{
  config = lib.mkIf (config.lib.neg.enabled "gui.hyprwhspr") {
    services.hyprwhspr-rs.enable = true;

    # Every transcription is encoded by a forked ffmpeg (WAV or FLAC — both go
    # through it), and the upstream unit inherits systemd's minimal PATH, which
    # has no ffmpeg: the recording is captured, then dropped with
    # "spawn ffmpeg … No such file or directory". Give the unit the system
    # profile next to the pinned ffmpeg so wl-copy/rocm-smi resolve too.
    systemd.user.services.hyprwhspr-rs.serviceConfig.Environment = [
      "PATH=${lib.makeBinPath [ pkgs.ffmpeg ]}:/run/current-system/sw/bin"
    ];

    systemd.tmpfiles.rules = [
      "d ${homeDir}/.config/hyprwhspr-rs 0755 ${mainUser} ${mainGroup} -"
      "L+ ${homeDir}/.config/hyprwhspr-rs/config.jsonc - ${mainUser} ${mainGroup} - ${hyprwhsprConfig}"
    ];

    # The Hyprland binds (M1+`) and the Vicinae extension exec `hyprwhspr-rs`
    # by name, so the daemon binary has to be on the session PATH; the service
    # unit itself uses the store path.
    environment.systemPackages = [ pkgs.hyprwhspr-rs ];
  };
}
