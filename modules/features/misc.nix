{ lib, ... }:
with lib;
let
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features = {
    text = {
      read.enable = mkBool "enable reading stack (CLI/GUI viewers, OCR, Recoll)" true;
      manipulate.enable = mkBool "enable text/markup manipulation CLI tools (jq/yq/htmlq)" true;
      notes.enable = mkBool "enable notes tooling (zk CLI)" true;
      tex.enable = mkBool "enable TeX/LaTeX stack (TexLive full, rubber)" false;
      espanso.enable = mkBool "enable espanso text expander" false;
    };

    # Fun/extras (e.g., curated art assets) that are nice-to-have
    fun = {
      enable = mkBool "enable fun extras (art collections, etc.)" true;
    };

    # GPG stack (gpg, gpg-agent, pinentry)
    gpg.enable = mkBool "enable GPG and gpg-agent (creates ~/.gnupg)" true;

    secrets = {
      enable = mkBool "enable secrets tooling (pass, YubiKey helpers)" true;
    };
  };
}
