{
  lib,
  config,
  ...
}: let
  xdg = import ../../lib/xdg-helpers.nix {inherit lib;};
  # Render current allowlist into a Nix list literal in the written config
  allowedListLiteral = "[ " + (lib.concatStringsSep " " (map (s: ''"'' + s + ''"'') config.features.allowUnfree.allowed)) + " ]";
  tpl = builtins.readFile ./nixpkgs-config.tpl;
  rendered = lib.replaceStrings ["@ALLOWED@"] [allowedListLiteral] tpl;
in
  xdg.mkXdgText "nixpkgs/config.nix" rendered
