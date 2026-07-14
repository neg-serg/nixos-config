{
  config,
  lib,
  neg,
  ...
}:
let
  inherit (config.users.users.neg) home;
in
{
  config = lib.mkIf (config.features.web.enable && config.features.web.tools.enable) (
    lib.mkMerge [
      {
        # aria2 is installed via cli/file-ops.nix
      }
      (neg.mkHomeFiles {
        # Use .local/share for session file (XDG_DATA_HOME typically)
        ".local/share/aria2/session".text = "";

        # Config file
        ".config/aria2/aria2.conf".text = ''
          dir=${home}/dw/aria
          enable-rpc=true
          save-session=${home}/.local/share/aria2/session
          input-file=${home}/.local/share/aria2/session
          save-session-interval=1800
        '';
      })
    ]
  );
}
