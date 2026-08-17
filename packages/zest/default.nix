##
# Package: zest
# Purpose: CLI for ZestBay plugin management — list/add/remove LV2 plugin
#   instances in the distrobox-hosted ZestBay (edits ~/.config/zestbay/plugins.json
#   and restarts ZestBay so changes are picked up).
{
  python3,
  writeShellScriptBin,
}:
writeShellScriptBin "zest" ''
  exec ${python3}/bin/python3 ${./zest.py} "$@"
''
