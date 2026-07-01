{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.hardware.audio.hdspe or { };

  # Set HDSPe mixer levels for analog outputs (1:1 playback→output routing)
  # The snd-hdspe driver initializes the hardware mixer to all zeros,
  # so we must set "Chn N" controls to 64 (= unity gain) for outputs to work.
  hdspeMixerScript = pkgs.writeShellScript "hdspe-init-mixer" ''
    set -euo pipefail
    amixer_bin=${pkgs.alsa-utils}/bin/amixer
    # Try common HDSPe ALSA card identifiers
    for card in "RMEAIO" "HDSPeAIO" "HDSPe" "AIO" "RME_AIO"; do
      if $amixer_bin -c "$card" info >/dev/null 2>&1; then
        $amixer_bin -c "$card" set "Chn 1" 64 >/dev/null 2>&1 || true
        $amixer_bin -c "$card" set "Chn 2" 64 >/dev/null 2>&1 || true
        exit 0
      fi
    done
    # Fallback: scan for any HDSPe card
    for card in $($amixer_bin cards 2>/dev/null | grep -i "hdsp\|rme.*aio" | awk '{print $1}' | tr -d ','); do
      [ -n "$card" ] || continue
      $amixer_bin -c "$card" set "Chn 1" 64 >/dev/null 2>&1 || true
      $amixer_bin -c "$card" set "Chn 2" 64 >/dev/null 2>&1 || true
      exit 0
    done
  '';

  # Set HDSPe as default PipeWire sink
  hdspeDefaultScript = pkgs.writeShellScript "wpctl-set-hdspe-default" ''
    set -euo pipefail
    jq_bin=${pkgs.jq}/bin/jq
    pw_dump_bin=${pkgs.pipewire}/bin/pw-dump
    wpctl_bin=${pkgs.pipewire}/bin/wpctl
    tries=60
    for i in $(seq 1 "$tries"); do
      dump="$("$pw_dump_bin" || true)"
      if [ -z "$dump" ]; then
        sleep 0.5
        continue
      fi
      sink_id="$("$jq_bin" -r '
        .[] | select(
          .type=="PipeWire:Interface:Node"
          and (
            (.info.props["node.name"] // "") | test("hdspe|HDSPe|rme.*aio|rme.*hdsp"; "i")
            or (.info.props["alsa.card_name"] // "") | test("HDSPe|AIO|RME"; "i")
          )
          and (.info.props["media.class"] == "Audio/Sink")
        ) | .id
      ' <<<"$dump" | head -n1 | tr -d '\n')"
      if [ -n "$sink_id" ]; then
        "$wpctl_bin" set-default "$sink_id" || true
        exit 0
      fi
      sleep 0.5
    done
    exit 0
  '';
in
{
  options.hardware.audio.hdspe = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable RME HDSPe support (mixer init, default PipeWire sink).";
    };
  };

  config = lib.mkIf cfg.enable {
    # System-level: initialize HDSPe hardware mixer on boot
    systemd.services."hdspe-init-mixer" = {
      description = "Initialize RME HDSPe hardware mixer levels";
      after = [ "alsa-store.service" "sound.target" ];
      wantedBy = [ "sound.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${hdspeMixerScript}";
      };
    };

    # User-level: set HDSPe as default PipeWire sink
    systemd.user.services."wp-hdspe-default" = {
      description = "Set RME HDSPe as default PipeWire sink";
      after = [
        "wireplumber.service"
        "pipewire.service"
      ];
      partOf = [ "wireplumber.service" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${hdspeDefaultScript}";
      };
    };
  };
}
