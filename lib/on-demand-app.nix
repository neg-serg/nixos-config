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
#
# Several commands can share one root (`aliases`): the invoked name selects the
# binary of the same name inside the package — mangohud ships mangohud,
# mangoapp, mangohudctl and mangoplot in one output, and gamescope's
# `--mangoapp` looks up `mangoapp` by name. `binary` covers the case where the
# launcher name is not the binary name (vital -> Vital).
{
  pkgs,
  nix ? pkgs.nix,
}:
{
  name,
  attr,
  binary ? name,
  aliases ? [ ],
}:
let
  lib = pkgs.lib;

  dispatch = pkgs.writeShellScript "${name}-on-demand" ''
    root="$HOME/.local/state/nix-apps/${name}"
    if [ ! -e "$root" ]; then
      mkdir -p "$(dirname "$root")"
      rm -f "$root"
      out=$(${nix}/bin/nix build --no-link --print-out-paths "git+file:///etc/nixos#${attr}" |
        while IFS= read -r candidate; do
          if [ -x "$candidate/bin/${binary}" ]; then
            printf '%s\n' "$candidate"
            break
          fi
        done)
      ${nix}/bin/nix-store --add-root "$root" --indirect --realise "$out" >/dev/null
    fi
    case "$(basename "$0")" in
      ${name}) exec "$root/bin/${binary}" "$@" ;;
      ${lib.concatMapStrings (a: "${a}) exec \"$root/bin/${a}\" \"$@\" ;;\n      ") aliases}
    esac
    exec "$root/bin/${binary}" "$@"
  '';
in
(pkgs.runCommand "${name}-launchers" { } ''
  mkdir -p $out/bin
  ${lib.concatMapStrings (n: "ln -s ${dispatch} $out/bin/${n}\n  ") ([ name ] ++ aliases)}
'').overrideAttrs
  (old: {
    # lib.getExe (the ollama module does that) otherwise warns about a missing
    # mainProgram on every evaluation.
    meta = (old.meta or { }) // {
      mainProgram = name;
    };
  })
