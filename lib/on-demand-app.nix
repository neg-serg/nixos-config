# On-demand launcher builder: keep an app's closure out of system-path.
#
# The launcher references only nix; the first run builds the matching flake
# package and registers a GC root under $HOME, later runs exec the binary
# directly. Refresh a root with `nix-apps update <name>` (modules/system/
# nix-apps.nix) instead of deleting it: the CLI rebuilds from the current
# flake, re-points the root and keeps the old path until the next GC.
#
# `--print-out-paths` prints one line per *output*, and multi-output packages
# (ffmpeg-full has out/dev/bin/man) would otherwise feed several paths into
# `nix-store --add-root` — it rejects the newline-joined string. Pick the output
# that actually carries bin/<binary> instead.
{ pkgs }:
{
  name,
  attr,
  binary ? name,
}:
pkgs.writeShellScriptBin name ''
  root="$HOME/.local/state/nix-apps/${name}"
  if [ ! -e "$root" ]; then
    mkdir -p "$(dirname "$root")"
    rm -f "$root"
    out=$(${pkgs.nix}/bin/nix build --no-link --print-out-paths "git+file:///etc/nixos#${attr}" |
      while IFS= read -r candidate; do
        if [ -x "$candidate/bin/${binary}" ]; then
          printf '%s\n' "$candidate"
          break
        fi
      done)
    ${pkgs.nix}/bin/nix-store --add-root "$root" --indirect --realise "$out" >/dev/null
  fi
  exec "$root/bin/${binary}" "$@"
''
