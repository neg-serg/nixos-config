##
# Module: media/audio/assets
# Purpose: Keep the audio *content* packages out of the system closure.
#
# Dirt-Samples, sc-faust and Renoise Redux are read only when a session starts.
# They used to enter the system derivation through nix-maid home-file symlinks
# (`.source` values are store paths), which cost 535 MiB in every switch and in
# the GC root of /run/current-system. Here they are built once per user into
# `~/.local/state/nix-apps/<name>` — the same GC-root convention as
# lib/on-demand-app.nix — and the symlinks in supercollider.nix plus
# SC_PLUGIN_PATH point at those roots instead of at store paths.
#
# The materialisation runs as a login oneshot, not from the activation script:
# activation must not need the network, and the first login is early enough for
# the samples/plugins to exist before a session is started by hand.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "media.audio.creation";

  # Attribute name in the repo flake == directory under the GC-root tree.
  assets = [
    "dirt-samples"
    "sc-faust"
    "renoise-redux"
    "flucoma"
  ];

  ensure = pkgs.writeShellScriptBin "audio-assets-ensure" ''
    set -eu
    nix=${config.nix.package}/bin/nix
    nixStore=${config.nix.package}/bin/nix-store

    # Roots are pinned to the nixpkgs revision that first built them, so after a
    # flake update they keep the old, still-working revision GC-rooted.
    # Refresh on demand: audio-assets-ensure --force (or systemctl --user start
    # audio-assets with AUDIO_ASSETS_FORCE=1).
    force=0
    case "''${1:-}" in --force) force=1 ;; esac
    [ "''${AUDIO_ASSETS_FORCE:-0}" = 1 ] && force=1

    for name in ${lib.concatStringsSep " " assets}; do
      root="$HOME/.local/state/nix-apps/$name"
      if [ -e "$root" ] && [ "$force" = 0 ]; then
        continue
      fi
      mkdir -p "$(dirname "$root")"
      rm -f "$root"
      out=$("$nix" build --no-link --print-out-paths "git+file:///etc/nixos#$name")
      "$nixStore" --add-root "$root" --indirect --realise "$out" >/dev/null
    done
  '';
in
{
  config = lib.mkIf enabled {
    # Maintenance entry point: `audio-assets-ensure [--force]`.
    environment.systemPackages = [ ensure ];

    systemd.user.services.audio-assets = config.lib.neg.systemdUser.mkUserOneshot {
      description = "Audio assets — materialise Dirt-Samples, sc-faust and Renoise Redux";
      script = "${ensure}/bin/audio-assets-ensure";
      after = [ "network.target" ];
    };
  };
}
