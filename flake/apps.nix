{
  self,
  inputs,
  pkgs,
  ...
}:
system:
let
  # nix-cache-pin apps (cache-pin-<pin> and the aggregate cache-pin); pins and
  # their JSON configs live in ./cache-pin.nix.
  cachePin = import ./cache-pin.nix { inherit inputs pkgs system; };
in
{
  apps = {
    # Same treefmt wrapper as the flake `formatter` output — single source of
    # truth (per-system.nix), so `nix run .#fmt` and `nix fmt` stay in sync.
    fmt = {
      type = "app";
      program = "${self.formatter.${system}}/bin/fmt";
    };

    # Heavy tools deliberately kept out of the system closure; run them with
    # `nix run .#<name>` or from their devshell.
    midi-transcribe = {
      type = "app";
      program = "${pkgs.neg.midi-transcribe}/bin/midi-transcribe";
    };
    docling = {
      type = "app";
      program = "${pkgs.neg.docling-env}/bin/docling";
    };
    faust2sc = {
      type = "app";
      program = "${pkgs.faust2sc}/bin/faust2sc";
    };
  }
  // cachePin.apps;
}
