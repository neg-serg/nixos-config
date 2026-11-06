##
# Module: text/wordcraft
# Purpose: WordCraft — Word-style word processor for .docx/.odt/.rtf, plus the
# `wordcraft-cli` document converter that ships in the same package.
{
  lib,
  config,
  pkgs,
  neg,
  ...
}:
let
  enabled = config.lib.neg.enabled "text.wordcraft";
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };
in
{
  config = lib.mkMerge [
    (lib.mkIf enabled {
      environment.systemPackages = lib.mkAfter [
        (onDemand {
          name = "wordcraft";
          attr = "wordcraft";
        }) # WordCraft desktop word processor, built on first use
        (onDemand {
          name = "wordcraft-cli";
          attr = "wordcraft";
          binary = "wordcraft-cli";
        }) # document converter shipped in the same package
        (pkgs.makeDesktopItem {
          name = "ai.storyteller.wordcraft";
          desktopName = "WordCraft";
          exec = "wordcraft %F";
          icon = "ai.storyteller.wordcraft";
          categories = [
            "Office"
            "WordProcessor"
          ];
          mimeTypes = [
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "application/vnd.ms-word.document.macroEnabled.12"
            "application/vnd.openxmlformats-officedocument.wordprocessingml.template"
            "application/vnd.ms-word.template.macroEnabled.12"
            "application/msword"
            "application/msword-template"
            "application/vnd.oasis.opendocument.text"
            "application/rtf"
            "text/rtf"
            "text/markdown"
            "text/x-tex"
            "text/html"
            "text/plain"
          ];
        })
      ];
    })

    # WordCraft scans the classic font folders itself (/usr/share/fonts and
    # ~/.local/share/fonts — crates/fonts/src/fontdb.rs) instead of asking
    # fontconfig, so the desktop would offer it nothing but Iosevka and a .docx
    # asking for Calibri/Cambria/Arial/Times would render with wrong metrics.
    # Link the metric-compatible substitutes — the same families the app's own
    # substitution table expects — into the user font folder, plus the coverage
    # fonts its fallback list wants for characters the document fonts lack
    # (CJK, emoji; the monochrome Noto Emoji renders in the rasteriser/PDF,
    # where a COLR/CBDT colour font has no guaranteed path).
    (lib.mkIf enabled (
      neg.mkHomeFiles {
        ".local/share/fonts/carlito".source = "${pkgs.carlito}/share/fonts"; # Calibri metrics
        ".local/share/fonts/caladea".source = "${pkgs.caladea}/share/fonts"; # Cambria metrics
        ".local/share/fonts/liberation".source = "${pkgs.liberation_ttf}/share/fonts"; # Arial/Times/Courier metrics
        ".local/share/fonts/dejavu".source = "${pkgs.dejavu_fonts}/share/fonts"; # Unicode/symbol fallback
        ".local/share/fonts/noto-cjk-sans".source = "${pkgs.noto-fonts-cjk-sans}/share/fonts"; # CJK fallback
        ".local/share/fonts/noto-emoji".source = "${pkgs.noto-fonts-monochrome-emoji}/share/fonts"; # emoji fallback
      }
    ))
  ];
}
