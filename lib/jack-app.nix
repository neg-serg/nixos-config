# PipeWire/JACK plumbing for application units — the two shapes the audio
# stack repeats, each one a `systemdUser.mkUserService` unit:
#
#   - mkUnit: a port *watcher*. pipewire-jack never auto-connects client ports
#     and WirePlumber ignores JACK nodes (they carry no media.class), so an app
#     that opens a JACK client comes up unlinked and silent until somebody runs
#     pw-link for it by hand — which dies with the next restart of the app.
#     The watcher polls `pw-link -o` and links the pair as soon as both ports
#     exist, so the app needs no cooperation and a restart costs nothing.
#   - mkPwJackUnit: launch a standalone app under pw-jack, on demand (the user
#     starts it), with the repo-wide restart policy.
#
# Both carry the shared audio-graph ordering ("audioGraph" preset: after
# pipewire + wireplumber) and the PATH those binaries come from, so a call site
# names only the client, its ports and the sink.
{
  lib,
  pkgs,
  pipewire,
  mkUserService,
}:
let
  # pw-jack from the same build as the running server: a unit must never mix a
  # JACK client library from one PipeWire build with a daemon from another.
  pwJack = pipewire.jack;

  # PipeWire appends -N to a client name while the previous node is still
  # registered (restart storm, two instances of the same app), so the port match
  # tolerates the suffix instead of pinning the bare name.
  portMatch = client: port: "^${client}[^:]*:${port}$";

  # PATH every unit here needs: pw-link/pw-jack, grep for the port match, sleep
  # for the poll interval. Callers add their own binaries via extraPath.
  basePath = [
    pipewire
    pkgs.gnugrep
    pkgs.coreutils
  ];

  # `"$src0"` in the generated shell. Concatenated instead of written out
  # because a `$` directly in front of a Nix `${` inside an indented string is
  # not what it looks like (the lexer folds the pair, and the interpolation is
  # silently lost — the script then carries a literal `$${src.var}`).
  varRef = src: "$" + src.var;

  mkScript =
    {
      name,
      client,
      pairs,
      sink,
      interval,
    }:
    let
      # One shell variable per source port; the index keeps them apart without
      # deriving a variable name from a port name.
      sources = lib.imap0 (i: pair: pair // { var = "src${toString i}"; }) pairs;
      poll =
        src:
        "  ${src.var}=$(pw-link -o 2>/dev/null | grep -m1 -E '${portMatch client src.from}' || true)\n";
      # A pair is linked only when every source port is there: linking half a
      # stereo pair plays mono until the second port appears anyway.
      present = lib.concatStringsSep " && " (map (src: "-n \"${varRef src}\"") sources);
      links = lib.concatMapStrings (
        src: "    pw-link \"${varRef src}\" ${sink}:${src.to} 2>/dev/null || true\n"
      ) sources;
    in
    pkgs.writeShellScript name ''
      set -u
      # Poll forever: the ports vanish on every app restart and come back under
      # the same name, and pw-link is cheap compared to the alternative (a
      # silent engine nobody notices for days).
      while true; do
      ${lib.concatMapStrings poll sources}  if [[ ${present} ]]; then
      ${links}  fi
        sleep ${toString interval}
      done
    '';
in
{
  # Link `client`'s out ports into `sink` (both names as JACK/PipeWire shows
  # them): pairs = [ { from = "output_01_left"; to = "playback_FL"; } … ].
  mkUnit =
    {
      name,
      description,
      client,
      pairs,
      sink,
      interval ? 2,
    }:
    mkUserService {
      inherit description;
      presets = [
        "audioGraph"
        "graphicalWanted"
        "restartOnFailure"
      ];
      serviceConfig = {
        Type = "simple";
        ExecStart = mkScript {
          inherit
            name
            client
            pairs
            sink
            interval
            ;
        };
        Environment = "PATH=${lib.makeBinPath basePath}";
      };
    };

  # Run a standalone synth/tracker under pw-jack. `command` is the app's
  # ExecStart tail (absolute store path); `environment` is the service
  # Environment string the app itself needs (Wayland socket, GL backend).
  mkPwJackUnit =
    {
      description,
      command,
      environment ? null,
      restartSec ? 3,
    }:
    mkUserService {
      inherit description;
      presets = [
        "audioGraph"
        "restartOnFailure"
      ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pwJack}/bin/pw-jack ${command}";
        RestartSec = restartSec;
      }
      // lib.optionalAttrs (environment != null) { Environment = environment; };
    };
}
