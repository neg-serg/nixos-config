##
# Package: renoise-osc
# Purpose: Send OSC messages to Renoise's built-in OSC server from the shell
#   (UDP 127.0.0.1:9002 by default). Commands: status/eval/reverb/load,
#   transport, bpm/lpb/tpl, loop, track/instr/device mixing, record (pw-record
#   of the Renoise audio) and raw OSC patterns; 'renoise-osc help <cmd>' has
#   examples. Dependency-free Python OSC sender; no python-osc. Also installs
#   renoise-reverb, renoise-record aliases and renoise-osc-config (pins
#   Config.xml to UDP on port 9002 — run with Renoise closed).
{
  lib,
  python3,
  symlinkJoin,
  writeShellScriptBin,
}:
symlinkJoin {
  name = "renoise-osc";
  meta = {
    description = "Send OSC messages to Renoise's built-in OSC server from the shell";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ]; # local-only package: no upstream maintainer to credit
  };
  paths = [
    (writeShellScriptBin "renoise-osc" ''
      exec ${python3}/bin/python3 ${./renoise-osc.py} "$@"
    '')
    (writeShellScriptBin "renoise-reverb" ''
      exec ${python3}/bin/python3 ${./renoise-osc.py} reverb "$@"
    '')
    (writeShellScriptBin "renoise-record" ''
      exec ${python3}/bin/python3 ${./renoise-osc.py} record "$@"
    '')
  ];
}
