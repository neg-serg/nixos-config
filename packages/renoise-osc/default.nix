##
# Package: renoise-osc
# Purpose: Send OSC messages to Renoise's built-in OSC server from the shell
#   (UDP 127.0.0.1:9002 by default): eval/reverb/load/transport/status plus raw
#   patterns. Dependency-free Python OSC sender; no python-osc. Also installs
#   renoise-reverb (insert native Reverb) and renoise-osc-config (pins
#   Config.xml to UDP on port 9002 — run with Renoise closed).
{
  python3,
  symlinkJoin,
  writeShellScriptBin,
}:
symlinkJoin {
  name = "renoise-osc";
  paths = [
    (writeShellScriptBin "renoise-osc" ''
      exec ${python3}/bin/python3 ${./renoise-osc.py} "$@"
    '')
    (writeShellScriptBin "renoise-reverb" ''
      exec ${python3}/bin/python3 ${./renoise-osc.py} reverb "$@"
    '')
  ];
}
