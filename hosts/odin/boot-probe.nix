{
  pkgs,
  ...
}:
# TEMPORARY boot-timing probe — remove once the greetd/greeter boot delay is
# resolved. Samples the first ~65s of every boot into /run/boot-probe.log:
#
#   * greetd pids (main process and its --session-worker child) as they appear,
#     so the delay between "greetd started" and the greeter PAM session can be
#     attributed to the parent (before fork) or the worker.
#   * active VT — checks whether a VT switch coincides with the delay.
#   * latency of a fresh-process pwd.getpwnam("greeter"): glibc consults
#     nscd/unscd first and only falls back to nsswitch after a 5s poll timeout,
#     so ~5000ms entries expose a stalled nscd during boot (one 5s stall per
#     lookup in every process that resolves a user or group).
#
# At the end of the window it also dumps systemd's own greetd timestamps.
let
  pwnamProbe = pkgs.writeText "boot-probe-pwnam.py" ''
    import pwd
    import time

    started = time.monotonic()
    try:
        pwd.getpwnam("greeter")
    except KeyError:
        pass
    print(int((time.monotonic() - started) * 1000))
  '';

  probeScript = pkgs.writeShellApplication {
    name = "boot-probe";
    runtimeInputs = [
      pkgs.coreutils # date, seq, cut, sleep
      pkgs.procps # pgrep for greetd/nscd pids
      pkgs.python3 # fresh-process passwd lookup
      pkgs.systemd # systemctl show at the end of the window
    ];
    text = ''
      log=/run/boot-probe.log
      : > "$log"

      for _ in $(seq 1 130); do
        printf '%s up=%s pwnam_ms=%s vt=%s greetd=%s nscd=%s\n' \
          "$(date +%H:%M:%S.%2N)" \
          "$(cut -d' ' -f1 /proc/uptime)" \
          "$(python3 ${pwnamProbe})" \
          "$(cat /sys/class/tty/tty0/active 2> /dev/null || echo -)" \
          "$(pgrep -x greetd | paste -sd, - || echo -)" \
          "$(pgrep -x nscd | paste -sd, - || echo -)" >> "$log"
        sleep 0.5
      done

      {
        echo "--- systemd greetd timestamps (monotonic us) ---"
        systemctl show greetd.service -p Type \
          -p ActiveEnterTimestampMonotonic \
          -p ExecMainStartTimestampMonotonic \
          -p NRestarts
      } >> "$log" 2>&1
    '';
  };
in
{
  systemd.services.boot-probe = {
    description = "Temporary boot-timing probe (greetd/nscd/VT)";
    wantedBy = [ "sysinit.target" ];
    after = [ "systemd-journald.service" ];
    serviceConfig = {
      # Type=simple: the unit counts as started as soon as the sampler is
      # spawned, so it never holds back the targets it is wanted by.
      Type = "simple";
      ExecStart = "${probeScript}/bin/boot-probe";
      StandardOutput = "null";
      StandardError = "null";
    };
  };
}
