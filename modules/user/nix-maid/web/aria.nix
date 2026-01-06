{
  config,
  lib,
  neg,
  impurity ? null,
  ...
}: let
  n = neg impurity;
in {
  config = lib.mkIf (config.features.web.enable && config.features.web.tools.enable) (lib.mkMerge [
    {
      # aria2 is installed via cli/file-ops.nix
    }
    (n.mkHomeFiles {
      # Use .local/share for session file (XDG_DATA_HOME typically)
      ".local/share/aria2/session".text = "";

      # Config file
      ".config/aria2/aria2.conf".text = ''
        dir=${config.users.users.neg.home}/dw/aria
        enable-rpc=true
        save-session=${config.users.users.neg.home}/.local/share/aria2/session
        input-file=${config.users.users.neg.home}/.local/share/aria2/session
        save-session-interval=1800
      '';
    })
  ]);
}
