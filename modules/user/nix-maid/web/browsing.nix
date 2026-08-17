{
  lib,
  config,
  neg,
  ...
}:
with lib;
let
  # --- SurfingKeys: Russian-layout ru2en table (ЙЦУКЕН) -----------------------
  # GENERATED from lib/ru-keys.nix (single source of truth) — do not edit the
  # chars. SurfingKeys matches vim keys by event.key; under ru every latin bind
  # breaks, so each Cyrillic letter maps to its Latin command.
  ruKeys = neg.ruKeys;

  # JS object literal entries: 'cyrillic':'latin' (ru key → en command).
  # A key/value containing a quote gets double quotes.
  skEntry =
    k:
    let
      v = ruKeys.toRu k;
    in
    "'${v}':${if k == "'" then "\"'\"" else "'${k}'"}";

  skRu2en =
    "const ru2en = { "
    + concatStringsSep ", " (map skEntry (filter (k: k != "`") (attrNames ruKeys.latinToRu)))
    + " };";

  skText =
    replaceStrings
      [
        "// @GENERATED ru2en — see modules/user/nix-maid/web/browsing.nix (skRu2en)"
      ]
      [
        skRu2en
      ]
      (builtins.readFile (config.lib.neg.path "files/surfingkeys.js"));
in
{
  imports = [
    ./defaults.nix
    ./surfingkeys-server.nix
  ];

  config = lib.mkMerge [
    (neg.mkHomeFiles {
      # surfingkeys.js: ru2en table is GENERATED (see skRu2en), rest as-is.
      ".config/surfingkeys.js".text = skText;
      # Vivaldi CSS mod: compact address bar (dir is set via css_ui_mods_directory pref)
      ".config/vivaldi/css-mods/compact-addressbar.css".source =
        config.lib.neg.path "files/vivaldi/compact-addressbar.css";
      # Vivaldi CSS mod: hide tab bar + window control buttons (single-bar layout)
      ".config/vivaldi/css-mods/minimal-ui.css".source =
        config.lib.neg.path "files/vivaldi/minimal-ui.css";
      # Vivaldi CSS mod: Iosevka Proportional across the whole browser chrome
      # (replaces the old /etc/vivaldi/custom-ui/ mechanism — see vivaldi.nix)
      ".config/vivaldi/css-mods/ui-font.css".source =
        config.lib.neg.path "files/vivaldi/ui-font.css";
    })
  ];
}
