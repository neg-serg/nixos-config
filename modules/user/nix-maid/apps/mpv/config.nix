{
  lib,
  config,
  neg,
  pkgs,
  ...
}:
let
  inherit (config.users.users.neg) home;
in
{
  config = lib.mkIf (config.lib.neg.enabled "gui") (
    lib.mkMerge [
      {
        environment.variables.MPV_HOME = "${home}/.config/mpv";
      }
      (neg.mkHomeFiles {
        ".config/mpv/mpv.conf".text = builtins.readFile (
          pkgs.replaceVars (config.lib.neg.path "files/mpv/mpv.conf") { inherit home; }
        );
        ".config/mpv/styles.ass".text = ''
          ##[V4+ Styles]
          Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
          Style: Default,Lucida Grande,20,&H00FFFFFF,&HF0000000,&H80000000,&HF0000000,0,0,0,0,100,100,0,0.00,1,2,0,2,30,30,20,1
        '';
      })
    ]
  );
}
