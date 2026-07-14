{
  pkgs,
  lib,
  config,
  neg,
  ...
}:

{
  config = lib.mkMerge [
    {
      environment.systemPackages = [
        pkgs.espanso # Cross-platform text expander
      ];
    }

    (neg.mkHomeFiles {
      ".config/espanso/config/default.yml".text = ''
        backend: Clipboard
        search_shortcut: ALT+SPACE
      '';
      ".config/espanso/match/base.yml".text = ''
        matches:
          - trigger: ":date"
            replace: "{{mydate}}"
          - trigger: ":time"
            replace: "{{mytime}}"
          - trigger: ":now"
            replace: "{{myname}}"
      '';
    })
  ];
}
