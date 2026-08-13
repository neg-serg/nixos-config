# Game Launchers Module
#
# Steam, Heroic, Prismlauncher and other game launchers.
{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  cfg = config.profiles.games or { };
in
{
  imports = [
    inputs.steam-config-nix.nixosModules.default # Steam declarative config injection
  ];

  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      package = pkgs.steam.override {
        # Digital distribution platform
        extraBwrapArgs = [
          "--bind"
          "/zero"
          "/zero"
          # CEF/Steam break through SOCKS5 (CM WebSocket ports reset, RSA-key
          # fetch fails): strip session proxy env vars so Steam always goes
          # direct. no_proxy does not help — Chromium ignores it for SOCKS5.
          "--unsetenv"
          "ALL_PROXY"
          "--unsetenv"
          "http_proxy"
          "--unsetenv"
          "https_proxy"
          "--unsetenv"
          "HTTP_PROXY"
          "--unsetenv"
          "HTTPS_PROXY"
          "--unsetenv"
          "all_proxy"
          # Route ALL Steam traffic (incl. native CM WebSocket on 27018-27036)
          # through the local SOCKS5 proxy via proxychains LD_PRELOAD — only
          # when features.games.steamProxy is enabled (re-injects the proxy
          # stripped above).
        ]
        ++ lib.optionals config.features.games.steamProxy.enable [
          "--setenv"
          "LD_PRELOAD"
          "${pkgs.proxychains}/lib/libproxychains4.so"
          # proxychains needs its config inside the sandbox (bwrap /etc is a
          # tmpfs with only whitelisted symlinks — /etc/proxychains is not one).
          "--ro-bind"
          "/etc/proxychains/proxychains.conf"
          "/etc/proxychains/proxychains.conf"
        ]
        ++ [
          # (e.g. Steam "Add Drive").  --ro-bind-try so it is a no-op when
          # the path does not exist.
          "--ro-bind-try"
          "/run/user/$UID/doc"
          "/run/user/$UID/doc"
        ];
        extraPkgs =
          pkgs':
          let
            mkDeps =
              pkgsSet: with pkgsSet; [
                # Common multimedia/system libs
                libxkbcommon # keyboard layout management
                freetype # font rendering engine
                fontconfig # font configuration library
                glib # core application building block
                libpng # PNG image format library
                libpulseaudio # PulseAudio client library
                pulseaudio # pactl CLI for PulseAudio volume/device control
                libvorbis # Vorbis audio codec
                libkrb5 # Kerberos 5 library
                keyutils # kernel key management utilities
                openal # multi-channel 3D audio API
                zlib # compression library
                libelf # ELF object file manipulation library
                attr # extended attributes library
                python3 # python interpreter
                zstd # fast lossless compression algorithm

                # GL/Vulkan plumbing for AMD on X11 (host RADV)
                libglvnd # vendor-neutral OpenGL dispatch library
                libdrm # direct rendering manager library
                vulkan-loader # Vulkan ICU loader
                libGLU # OpenGL utility library

                # libstdc++ for the runtime
                (lib.getLib stdenv.cc.cc)

                # Network/Auth libs often needed by Steam Runtime tools
                openssl # cryptography library
                libpsl # public suffix list library
                nghttp2 # HTTP/2 implementation
                libidn2 # IDNA2008 implementation
              ];
          in
          mkDeps pkgs';
      };
      dedicatedServer.openFirewall = true;
      gamescopeSession.enable = true;
      remotePlay.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      extraCompatPackages = [ pkgs.proton-ge-bin ]; # community Proton build with more patches
    };

    # Steam cannot route its native CM connections (WebSocket 27018-27036)
    # through SOCKS5 via env vars — it ignores ALL_PROXY. When
    # features.games.steamProxy is enabled, the launcher above is wrapped with
    # proxychains LD_PRELOAD so all outbound TCP goes through the local SOCKS5
    # proxy. Env proxies are stripped inside to avoid double-routing.
    environment.etc."proxychains/proxychains.conf" = lib.mkIf config.features.games.steamProxy.enable {
      text = ''
        strict_chain
        proxy_dns
        remote_dns_subnet 224
        tcp_read_time_out 15000
        tcp_connect_time_out 8000
        localnet 127.0.0.0/255.0.0.0
        [ProxyList]
        socks5 127.0.0.1 10808
      '';
    };

    environment.systemPackages = [
      pkgs.protontricks # winetricks-like helper tailored for Steam Proton
    ];

    # Expose udev rules/devices used by various game controllers
    hardware.steam-hardware.enable = true;
  };
}
