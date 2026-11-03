# On-demand launcher builder: keep an app's closure out of system-path.
#
# The launcher references only nix; the first run builds the matching flake
# package and registers a GC root under $HOME, later runs exec the binary
# directly. Rebuild/update by removing the root directory and running again.
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
    out=$(${pkgs.nix}/bin/nix build --no-link --print-out-paths "git+file:///etc/nixos#${attr}")
    ${pkgs.nix}/bin/nix-store --add-root "$root" --indirect --realise "$out" >/dev/null
  fi
  exec "$root/bin/${binary}" "$@"
''
