{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.features.web.enable && config.features.web.tools.enable) {
    # Install aria2
    environment.systemPackages = [pkgs.aria2];

    users.users.neg.maid = {
      # Session file kept in XDG data (persist resume state)
      # Ensure the session file exists under XDG data
      file.xdg_data."aria2/session".text = "";

      # Config file
      file.xdg_config."aria2/aria2.conf".text = ''
        dir=${config.users.users.neg.home}/dw/aria
        enable-rpc=true
        save-session=${config.users.users.neg.home}/.local/share/aria2/session
        input-file=${config.users.users.neg.home}/.local/share/aria2/session
        save-session-interval=1800
      '';
    };
  };
}
