{
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  cfg = config.features;
  filesRoot = ../../../../files;
in
{
  config = lib.mkMerge [
    (lib.mkIf (cfg.games.dosemu.enable or false) (
      n.mkHomeFiles {
        ".dosemu/disclaimer".source = "${filesRoot}/dosemu/disclaimer";
        ".dosemu/boot.log".source = "${filesRoot}/dosemu/boot.log";
        ".dosemu/drive_c/autoexec.bat".source = "${filesRoot}/dosemu/drive_c/autoexec.bat";
        ".dosemu/drive_c/config.sys".source = "${filesRoot}/dosemu/drive_c/config.sys";
      }
    ))

    (n.mkHomeFiles {
      # Dosbox Config
      ".config/dosbox".source = ../../../../files/config/dosbox;

    })
  ];
}
