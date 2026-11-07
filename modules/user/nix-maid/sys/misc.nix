{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  cfg = config.features;

  # Resolve a path under files/ from the repo root
  files = p: config.lib.neg.path ("files/" + p);

  # Rustmission Config Dir
  rustmissionConf = files "config/rustmission";
in
{
  config = lib.mkMerge [
    # Wine is not part of the system image: the wine this block used to install
    # was a leftover that kept the 1.7 GiB Wine closure there. It now comes from
    # the on-demand launchers in modules/system/wine-apps.nix when needed.
    (lib.mkIf (cfg.fun.enable or false) {
      # Cursed-text generator: a Rust package now (packages/zalgo), so the
      # executable comes from the overlay instead of a script in hack-art.
      users.users.neg.packages = [ pkgs.neg.zalgo ];
    })
    (lib.mkIf (cfg.fun.enable or false) (
      neg.mkHomeFiles (
        lib.mkMerge [
          # Rustmission
          {
            ".config/rustmission/config.toml".source = "${rustmissionConf}/config.toml";
            ".config/rustmission/keymap.toml".source = "${rustmissionConf}/keymap.toml";
            ".config/rustmission/categories.toml".source = "${rustmissionConf}/categories.toml";
          }
        ]
      )
    ))

  ];
}
