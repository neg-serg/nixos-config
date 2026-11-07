{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  # espanso links wxwidgets/WebKit (176 MiB) for a text expander that is
  # started by hand, so the launcher builds it on first use instead of
  # carrying the toolkit in every system generation.
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };
in

{
  config = lib.mkMerge [
    {
      environment.systemPackages = [
        (onDemand {
          name = "espanso";
          attr = "espanso";
        }) # cross-platform text expander, built on first use
      ];
    }

    (neg.mkHomeFiles {
      ".config/espanso/config/default.yml".text = ''
        backend: Clipboard
        search_shortcut: ALT+SHIFT+SPACE
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
