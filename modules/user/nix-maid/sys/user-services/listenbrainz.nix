##
# Module: user/nix-maid/sys/user-services/listenbrainz
# Purpose: listenbrainz-mpd — MPD -> ListenBrainz scrobbler as a systemd user
#          unit. The Last.fm-free counterpart to the mpdas unit in
#          media-proxy.nix; both can run side by side.
# Key options: features.media.audio.listenbrainzMpd.{enable,apiUrl}
# Secret: secrets/home/listenbrainz-mpd.sops.yaml (key `token`); the unit is
#         emitted only when that file exists, so enabling the flag without the
#         secret is a no-op.
# Dependencies: config.toml and the sops secret are declared in sys/media.nix.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  systemdUser = config.lib.neg.systemdUser;
  enabled =
    config.lib.neg.enabled "media.audio.listenbrainzMpd"
    && config.lib.neg.enabled "media.audio.mpd"
    && config.lib.neg.pathExists "secrets/home/listenbrainz-mpd.sops.yaml";
in
{
  systemd.user.services.listenbrainz-mpd = lib.mkIf enabled (
    systemdUser.mkUserService {
      presets = [
        "defaultWanted"
        "restartOnFailure"
      ];
      description = "MPD -> ListenBrainz scrobbler";
      # Same reasoning as the mpdas unit: no after/wants on mpd.service — in the
      # user session that name resolves to the config-less mpd package unit, not
      # the real system MPD. listenbrainz-mpd connects to MPD over TCP itself
      # and retries failed listens from its own SQLite cache.
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.listenbrainz-mpd} --config %h/.config/listenbrainz-mpd/config.toml";
      };
    }
  );
}
