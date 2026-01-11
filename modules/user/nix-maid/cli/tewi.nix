{
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  cfg = config.features.cli.tewi;
  tewiConf = ''
    [client]
    # BitTorrent client type: transmission, qbittorrent, or deluge
    # type = transmission
    # host = localhost
    # port = 9091
    # path = /transmission/rpc

    [ui]
    view_mode = oneline
    page_size = 50
    filter = all
    badge_max_count = 3
    badge_max_length = 10
    refresh_interval = 2

    [search]
    jackett_url = http://localhost:9117
    prowlarr_url = http://localhost:9696
    providers =

    [debug]
    logs = false
  '';
in
{
  config = lib.mkIf (cfg.enable or false) (
    n.mkHomeFiles {
      ".config/tewi/tewi.conf".text = tewiConf;
    }
  );
}
