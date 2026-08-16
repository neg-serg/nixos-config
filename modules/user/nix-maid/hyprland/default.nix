# environment.nix / files.nix / services.nix are helper modules imported by
# main.nix as plain functions — not NixOS modules, so the entry is manual.
{
  imports = [
    ./main.nix
    ./ru-layout.nix
  ];
}
