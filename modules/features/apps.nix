{ mkBool, ... }:
{
  options.features.apps = {
    # Throne (formerly Nekoray): Qt GUI on top of sing-box/Xray for editing
    # proxy profiles, importing subscriptions and testing servers by hand. The
    # package alone opens nothing — no service, no autostart — and binds a port
    # only when launched. Do not run it next to the `sing-box-proxy` user unit:
    # both want a local inbound, and 127.0.0.1:10808 is this host's convention.
    throne = {
      enable = mkBool "install Throne (GUI profile manager for sing-box/Xray proxies, manual start only)" false;
      # TUN mode needs CAP_NET_ADMIN, which the nixpkgs module grants through a
      # capability wrapper around ThroneCore (`security.wrappers`) plus a polkit
      # rule for resolved. That is a root-adjacent surface, so it stays a
      # separate opt-in, off even when the GUI itself is installed.
      tunMode.enable = mkBool "grant ThroneCore the capabilities for TUN mode (CAP_NET_ADMIN, CAP_NET_RAW, CAP_NET_BIND_SERVICE)" false;
    };
    # ArtCraft suite (VectorCraft, FigCraft, SoundCraft, DeckCraft, GridCraft,
    # SolidCraft): launchers + desktop entries only, every app builds on first
    # launch (modules/user/nix-maid/apps/craft-apps.nix).
    craftApps.enable = mkBool "install the ArtCraft suite as on-demand launchers (vector, design, DAW, slides, sheets, CAD)" false;
  };
}
