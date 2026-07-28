{
  pkgs,
  lib,
  preCommit,
  ...
}:
{
  default = import ./base.nix { inherit pkgs lib preCommit; };
  tools = import ./tools.nix { inherit pkgs lib; };
  haskell = import ./haskell.nix { inherit pkgs lib; };
  rust = import ./rust.nix { inherit pkgs lib; };
  cpp = import ./cpp.nix { inherit pkgs lib; };
  java = import ./java.nix { inherit pkgs lib; };
  re = import ./re.nix { inherit pkgs lib; };
  infra = import ./infra.nix { inherit pkgs lib; };
  python = import ./python.nix { inherit pkgs lib; };
  android = import ./android.nix { inherit pkgs lib; };
  qmk = import ./qmk.nix { inherit pkgs lib; };
  radicle = import ./radicle.nix { inherit pkgs lib; };
  pentest = import ./pentest.nix { inherit pkgs lib; };
  elf = import ./elf.nix { inherit pkgs lib; };
  graphics = import ./graphics.nix { inherit pkgs lib; };
  latex = import ./latex.nix { inherit pkgs lib; };
  misc = import ./misc.nix { inherit pkgs lib; };
  media = import ./media.nix { inherit pkgs lib; };
  virt = import ./virt.nix { inherit pkgs lib; };
  text = import ./text.nix { inherit pkgs lib; };
  "pro-audio" = import ./pro-audio.nix { inherit pkgs lib; };
  "web-archive" = import ./web-archive.nix { inherit pkgs lib; };
  db = import ./db.nix { inherit pkgs lib; };
  k8s = import ./k8s.nix { inherit pkgs lib; };
  wine = import ./wine.nix { inherit pkgs lib; };
}
