{
  lib,
  config,
  pkgs,
  xdg,
  ...
}:
lib.mkMerge [
  {
    # Ensure rmpc is installed
    home.packages = config.lib.neg.pkgsList [
      pkgs.rmpc # TUI MPD client (Rust)
    ];
  }
  # Live-editable config via helper (guards parent dir and target)
  (xdg.mkXdgSource "rmpc" {
    source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/media/audio/rmpc/conf";
    recursive = true;
  })
]
