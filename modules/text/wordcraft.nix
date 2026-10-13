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
in
{
  config = lib.mkMerge [
    (lib.mkIf enabled {
      environment.systemPackages = lib.mkAfter [
        pkgs.wordcraft # WordCraft: desktop word processor + wordcraft-cli converter (docx/pdf/odt/rtf/md/…)
      ];
    })

    # WordCraft scans the classic font folders itself (/usr/share/fonts and
    # ~/.local/share/fonts — crates/fonts/src/fontdb.rs) instead of asking
    # fontconfig, so the desktop would offer it nothing but Iosevka and a .docx
    # asking for Calibri/Cambria/Arial/Times would render with wrong metrics.
    # Link the metric-compatible substitutes — the same families the app's own
    # substitution table expects — into the user font folder.
    (lib.mkIf enabled (
      neg.mkHomeFiles {
        ".local/share/fonts/carlito".source = "${pkgs.carlito}/share/fonts"; # Calibri metrics
        ".local/share/fonts/caladea".source = "${pkgs.caladea}/share/fonts"; # Cambria metrics
        ".local/share/fonts/liberation".source = "${pkgs.liberation_ttf}/share/fonts"; # Arial/Times/Courier metrics
        ".local/share/fonts/dejavu".source = "${pkgs.dejavu_fonts}/share/fonts"; # Unicode/symbol fallback
      }
    ))
  ];
}
