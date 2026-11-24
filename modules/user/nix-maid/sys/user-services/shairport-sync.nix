##
# Module: user/nix-maid/sys/user-services/shairport-sync
# Purpose: AirPlay 1 (RAOP) receiver as a systemd *user* unit, so the decoded
# stream lands in the session PipeWire graph.
#
# Why a user unit and not services.shairport-sync: the nixpkgs module runs the
# daemon as the system user `shairport` (uid 989) with no XDG_RUNTIME_DIR, so
# the PipeWire backend resolves to /run/user/989/pipewire-0 — a socket that
# does not exist while the session graph listens on /run/user/1000. Sessions
# are accepted and decoded, no error reaches the journal at verbosity 1, and no
# client ever shows up in `pw-dump` (verified 2026-11-24 with a real RAOP
# stream). As the main user the unit inherits XDG_RUNTIME_DIR plus the
# PipeWire/WirePlumber user units, which is the only wiring libpipewire needs.
#
# The nixpkgs build has the PipeWire backend compiled in (version string carries
# "-PipeWire-"); nixpkgs' AirPlay 2 option stays off, so the receiver is classic
# RAOP. Firewall ports are the host policy's, not the module's openFirewall:
# tcp/5000 and udp/6001-6011 are already opened on net1 in
# hosts/trantor/services/policy.nix.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  # Module-shaped systemd user units (lib/systemd-user.nix)
  systemdUser = config.lib.neg.systemdUser;

  # libconfig file (same syntax the nixpkgs module generates). The name is what
  # iPhone/Mac/iTunes show in the AirPlay picker.
  #
  # `pipewire.sink_target` pins AirPlay to the monitors' DSP input instead of the
  # default sink, so AirPlay keeps playing on the RME AES pair whichever output
  # `pwout` selects for the desktop (`pwout headphones` sends everything else to
  # the E1DA; AirPlay stays on the monitors).
  #
  # The target is `game-stereo`, not the RME hardware node: targeting the RME sink
  # bypassed CamillaDSP (room correction) and ran the stream through pwroute's
  # monitor_AUX0/1 -> playback_AUX2/3 loop, which audibly worsened the sound
  # (2026-11-24). dsp/route.sh starts the insert when an app plays into
  # game-stereo — not only when that sink is the default — and keeps
  # camilladsp-playback on AES (files/media/hdspe-routing.yaml: aes = channels
  # 2/3), so the normal DSP path is what AirPlay should take.
  configFile = pkgs.writeText "shairport-sync.conf" ''
    general = {
      name = "Trantor AirPlay";
      output_backend = "pipewire";
    };
    pipewire = {
      sink_target = "game-stereo";
    };
    diagnostics = {
      log_verbosity = 1;
    };
  '';
in
{
  systemd.user.services.shairport-sync = systemdUser.mkUserService {
    presets = [
      "defaultWanted"
      "audioGraph"
      "restartOnFailure"
    ];
    description = "shairport-sync AirPlay receiver (user PipeWire output)";
    # The preset only carries After=; pull the audio units in as well so a
    # session that starts without PipeWire still brings the receiver up.
    wants = [
      "pipewire.service"
      "wireplumber.service"
    ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.shairport-sync} -c ${configFile}";
      RestartSec = "3s";
    };
  };
}
