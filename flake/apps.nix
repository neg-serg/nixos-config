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
    torch-rocm = {
      type = "app";
      program = "${pkgs.writeShellScriptBin "torch-rocm" ''
        exec env -u PYTHONPATH ${pkgs.torchRocmEnv}/bin/python "$@"
      ''}/bin/torch-rocm";
    };
    midi-transcribe = {
      type = "app";
      program = "${pkgs.neg.midi-transcribe}/bin/midi-transcribe";
    };
  }
  // cachePin.apps;
}
