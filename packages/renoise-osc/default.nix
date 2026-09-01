##
# Package: renoise-osc
# Purpose: Send OSC messages to Renoise's built-in OSC server from the shell,
#   primarily /renoise/evaluate (remote Lua) so devices/transport can be driven
#   without the mouse. Dependency-free Python OSC sender (UDP, no python-osc).
#   Also installs renoise-reverb: insert native Reverb on master or a track.
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
