{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.gui;
  # Module-shaped systemd user units (lib/systemd-user.nix)
  systemdUser = config.lib.neg.systemdUser;

  # Applies the saved "neg" profile at session start, with a short wake-up
  # animation: the controllers first run an effect for a moment, then the profile
  # colour is ramped in and the profile state is set for real.
  #
  # Two OpenRGB behaviours make the obvious `openrgb -p <profile>` useless here:
  #   * profile entries are matched by type/name/serial/location, and the /dev/i2c-N
  #     and /dev/hidrawN numbers inside those locations are not stable across boots
  #     — one more adapter shifts every number, so a profile saved weeks earlier
  #     matches nothing while the CLI still prints "Profile loaded successfully";
  #   * with the SDK server up, a plain `openrgb -p …` only connects as a client and
  #     the load never reaches the devices (verified: the server's controller state
  #     does not change at all).
  #
  # So the wrapper reads the profile, matches its entries against the live device
  # list by name (duplicates pair up in profile order, controllers without LEDs are
  # skipped) and replays it as per-device commands through the server, which is the
  # path that does reach the hardware:
  #   wake effect → colour ramp (30 %, 65 %) → the profile's own mode and colours.
  # Entries that describe the same device name and state are applied once for all
  # of them, so a two-DIMM kit costs one command per step instead of two.
  applyProfile = pkgs.writeShellScript "openrgb-apply-profile" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.openrgb # talks to the SDK server and drives the devices
        pkgs.jq # reads the profile, builds the command plan
        pkgs.coreutils # seq/sleep used below
      ]
    }:$PATH"
    set -euo pipefail

    profile=''${1:-$HOME/.config/OpenRGB/profiles/neg.json}
    wake_hold=2 # seconds the wake effect runs before the colour ramp starts
    ramp_pause=0.5 # seconds between colour ramp steps

    if [ ! -r "$profile" ]; then
      echo "openrgb-apply-profile: no profile at $profile, nothing to apply" >&2
      exit 0
    fi

    # Wait for the SDK server: it enumerates i2c while starting up, and it is what
    # reports the live devices and applies the commands to them.
    for _ in $(seq 1 30); do
      (exec 3<>/dev/tcp/127.0.0.1/6742) 2>/dev/null && break
      sleep 2
    done

    # Live device list as JSON: [{"index": 0, "name": "ENE DRAM"}, …]
    devices=$(
      openrgb --list-devices 2>/dev/null |
        jq -Rs '
          split("\n")
          | map(select(test("^[0-9]+: ")) | capture("^(?<index>[0-9]+): (?<name>.*)$"))
          | map({ index: (.index | tonumber), name })
        '
    )
    if [ "$(printf '%s' "$devices" | jq 'length')" -eq 0 ]; then
      echo "openrgb-apply-profile: SDK server reported no devices" >&2
      exit 1
    fi

    # The plan is one step per line: "<target>\t<mode>\t<colours>\t<kind>".
    # The target is a device name when every device with that name gets the same
    # state (one command for the whole kit), otherwise a device index. The kinds
    # are "wake" (an effect to come alive), "ramp" (the profile colour, dimmed) and
    # "final" (the profile state itself).
    plan=$(
      jq -r --argjson devices "$devices" '
        def hex6:
          ["0","1","2","3","4","5","6","7","8","9","A","B","C","D","E","F"] as $h
          | (. % 16777216) as $v
          | [ $h[($v / 1048576 | floor) % 16],
              $h[($v / 65536 | floor) % 16],
              $h[($v / 4096 | floor) % 16],
              $h[($v / 256 | floor) % 16],
              $h[($v / 16 | floor) % 16],
              $h[$v % 16] ]
          | add;
        def scaled($pct):
          (. % 16777216) as $v
          | (($v / 65536 | floor) * $pct / 100 | floor) * 65536
            + ((($v / 256 | floor) % 256) * $pct / 100 | floor) * 256
            + (($v % 256) * $pct / 100 | floor);
        def ramp($colours): [30, 65][] as $pct | $colours | map(scaled($pct)) | map(hex6) | join(",");
        def colours: map(hex6) | join(",");

        (reduce .controllers[] as $c
           ({ rest: $devices, pairs: [] };
            ($c.name) as $name
            | (.rest | map(select(.name == $name)) | first) as $live
            | if $live == null or ($c.leds | length) == 0 then .
              else { rest: (.rest - [$live]),
                     pairs: (.pairs + [{ index: $live.index, name: $name, entry: $c }]) }
              end)
         | .pairs)
        | map({ index,
                name,
                modes: (.entry.modes | map({ name, color_mode })),
                mode: .entry.modes[.entry.active_mode].name,
                uses_colours: (.entry.modes[.entry.active_mode].color_mode != 0),
                colours: (.entry.colors // []) })
        | group_by(.name)
        | map(
            if (map([.mode, .colours]) | unique | length) == 1 then
              { target: .[0].name } + (.[0] | del(.index, .name))
            else
              .[] | { target: (.index | tostring) } + (del(.index, .name))
            end)
        | .[]
        | . as $group
        | ($group.modes | map(.name)) as $available
        | (["Rainbow", "Spectrum Cycle", "Breathing", "Chase Fade"]
           | map(select(. as $candidate | ($available | index($candidate)) != null))
           | map(select(. != $group.mode))
           | first) as $wake
        | (
            (if $wake == null then empty
             else { mode: $wake,
                    colours: (if ($group.modes | map(select(.name == $wake)) | .[0].color_mode) != 0
                              then ($group.colours | colours) else "" end),
                    kind: "wake" }
             end),
            (if $group.uses_colours and ($group.colours | length) > 0
             then { mode: $group.mode, colours: ramp($group.colours), kind: "ramp" } else empty end),
            { mode: $group.mode,
              colours: (if $group.uses_colours then ($group.colours | colours) else "" end),
              kind: "final" }
          )
        | "\($group.target)\t\(.mode)\t\(if .colours == "" then "-" else .colours end)\t\(.kind)"
      ' "$profile"
    )

    if [ -z "$plan" ]; then
      echo "openrgb-apply-profile: no profile device matches the live devices" >&2
      exit 1
    fi

    echo "openrgb-apply-profile: $(basename "$profile") → $(printf '%s\n' "$plan" | wc -l) steps, $(printf '%s\n' "$plan" | cut -f1 | sort -u | tr '\n' ' ')"
    failed=0
    while IFS=$'\t' read -r target mode colours kind; do
      [ "$colours" = "-" ] && colours="" # empty colours survive the tab-separated plan
      args=(-d "$target" -m "$mode")
      [ -n "$colours" ] && args+=(-c "$colours")
      label="$target: $mode"
      [ -n "$colours" ] && label="$label ($colours)"

      case "$kind" in
        final)
          # The state that has to stick — retried, and the only step that can fail
          # the unit.
          settled=0
          for attempt in 1 2 3; do
            if openrgb "''${args[@]}" >/dev/null 2>&1; then
              settled=1
              break
            fi
            sleep 2
          done
          if [ "$settled" -eq 1 ]; then
            echo "openrgb-apply-profile: settled $label"
          else
            echo "openrgb-apply-profile: FAILED to settle $label" >&2
            failed=$((failed + 1))
          fi
          ;;
        wake)
          openrgb "''${args[@]}" >/dev/null 2>&1 || true
          echo "openrgb-apply-profile: woke $label"
          sleep "$wake_hold"
          ;;
        *)
          openrgb "''${args[@]}" >/dev/null 2>&1 || true
          echo "openrgb-apply-profile: faded in $label"
          sleep "$ramp_pause"
          ;;
      esac
    done <<< "$plan"

    [ "$failed" -eq 0 ] || exit 1
  '';

in
lib.mkIf (cfg.enable or false) {
  systemd.user.services = {
    # OpenRGB daemon — starts the SDK server so clients (profile service, GUI) can connect.
    # The profile is NOT loaded on daemon startup (it may not exist yet); the
    # openrgb-profile unit applies the saved profile once the server answers.
    openrgb = systemdUser.mkUserService {
      presets = [
        "graphicalSession"
        "restartOnFailure"
      ];
      description = "OpenRGB SDK server";
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.openrgb} --server"; # SDK server for RGB control
        RestartSec = "30";
      };
    };

    # OpenRGB profile — the session's lighting entrance: wake effect, colour ramp,
    # then the saved profile state. A missing profile is not an error (the applier
    # exits 0 quietly), and devices the profile knows but the machine does not have
    # right now are skipped.
    #
    # Type=exec and no fixed settle delay: this unit is WantedBy
    # graphical-session.target, and systemd orders such units Before= the target,
    # so a oneshot (or `ExecStartPre=sleep 10`) makes the whole session wait for
    # the delay. Journal 2026-09-19: "Starting Apply OpenRGB neg profile"
    # 18:25:52.689 → "Reached target Hyprland compositor session" 18:26:03.73 —
    # hypridle, vicinae, kanata, the portals and the bar were all dispatched 10.4 s
    # after the password, for a delay nothing on screen asked for. Type=exec marks
    # the unit started as soon as the process is spawned; the applier waits for the
    # SDK server itself, so no sleep is needed here.
    openrgb-profile = systemdUser.mkUserService {
      presets = [
        "graphicalWanted"
        "restartOnFailure"
      ];
      description = "Apply the OpenRGB lighting profile";
      after = [ "openrgb.service" ];
      requires = [ "openrgb.service" ];
      # startLimit* are unit-level options: expressed through unitConfig so the
      # rest of the unit still goes through the shared constructor.
      unitConfig = {
        StartLimitIntervalSec = 120;
        StartLimitBurst = 6;
      };
      serviceConfig = {
        Type = "exec";
        ExecStart = "${applyProfile} %h/.config/OpenRGB/profiles/neg.json";
        RemainAfterExit = false;
        # 10 s: the delay this unit has always used.
        RestartSec = 10;
      };
    };
  };
}
