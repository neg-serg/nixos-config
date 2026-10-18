# Unity Hub / Unity CLI through the local SOCKS5 proxy.
#
# Unity Hub is not packaged here: it is installed by hand from the official
# .deb (`~/opt/unityhub`, started by `run-hub.sh`), and the Hub keeps writing
# its own copy of the `unity` CLI to `~/.local/bin/unity`. What this module
# adds is proxy-aware launching:
#
#   unityhub-proxy — the Electron Hub (GUI) through the local SOCKS5 proxy
#   unity-proxy    — the Hub-installed `unity` CLI through the same proxy
#   a desktop entry for the GUI launcher
#
# Proxy environment variables alone are not enough for either of them: the Hub
# is Chromium, which ignores `http_proxy`/`https_proxy` on Linux (it reads the
# DE proxy settings instead), and the CLI ships its own network stack. Routing
# is therefore done by the proxychains LD_PRELOAD hook — the same mechanism the
# Steam wrapper uses (`modules/user/games/launchers.nix`). The `proxychains4`
# launcher binary cannot be used here: this build searches /usr/lib, /lib64 for
# its library, so only an explicit LD_PRELOAD finds the Nix store copy. The CLI
# additionally gets the usual `*_proxy` variables, which self-contained
# binaries do honour; the two mechanisms do not fight, because proxychains
# keeps loopback direct and the SOCKS endpoint is on loopback.
#
# Children (Unity Editor, UnityLicensingClient) inherit both, so an Editor
# started from the Hub reaches packages.unity.com and the license service
# through the proxy as well.
#
# One child needs an extra pin: Unity.Licensing.Client is .NET 7, and .NET opens
# dual-stack AF_INET6 sockets, so the fake-DNS address proxychains hands back
# (224.0.0.1) was connected to as ::ffff:224.0.0.1, bypassing the hook and dying
# with ENETUNREACH — license activation failed with "[1500] Internal Client
# Error: Network is unreachable". `DOTNET_SYSTEM_NET_DISABLEIPV6=1` forces IPv4
# sockets, which the hook does rewrite; see the comment at the launcher.
#
# The GUI launcher needs a second layer on top: Chromium's network stack issues
# its connects without going through libc, so the LD_PRELOAD hook never sees it
# (verified with `ss -tnp`: only the Hub browser process, the `unity` CLI and
# Unity.Licensing held sockets on 10808, while the in-app auth window failed
# with ERR_CONNECTION_REFUSED). Hence `--proxy-server=socks5://…` for the
# Electron side, on top of the hook for everything native.
#
# The endpoint is the sing-box SOCKS5 inbound of the `proxy` CLI on
# 127.0.0.1:10808 (`docs/runbook-proxy.md`), so this module is only meaningful
# with `features.net.proxy.enable`, which owns that service.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.dev.unity or { };
  enabled = (config.lib.neg.enabled "dev") && (cfg.enable or false);

  proxyHost = "127.0.0.1";
  proxyPort = 10808;
  proxyUrl = "socks5://${proxyHost}:${toString proxyPort}";
  preloadLib = "${pkgs.proxychains}/lib/libproxychains4.so";

  # A store path, not /etc/proxychains/proxychains.conf: that file belongs to
  # the Steam wrapper (`modules/user/games/launchers.nix`) and two modules
  # cannot define the same /etc path.
  proxychainsConf = pkgs.writeText "unity-proxychains.conf" ''
    strict_chain
    proxy_dns
    remote_dns_subnet 224
    tcp_read_time_out 15000
    tcp_connect_time_out 8000
    # Loopback stays direct: the SOCKS5 endpoint itself, Hub IPC and the
    # Unity license client sockets.
    localnet 127.0.0.0/255.0.0.0
    [ProxyList]
    socks5 ${proxyHost} ${toString proxyPort}
  '';
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = [
      pkgs.proxychains # LD_PRELOAD hook that routes libc clients through SOCKS5

      (pkgs.writeShellScriptBin "unityhub-proxy" ''
        export PROXYCHAINS_CONF_FILE=${proxychainsConf}
        export PROXYCHAINS_QUIET_MODE=1
        export LD_PRELOAD=${preloadLib}''${LD_PRELOAD:+:$LD_PRELOAD}
        # The Hub spawns Unity.Licensing.Client (.NET 7) and it inherits this
        # environment. .NET opens dual-stack AF_INET6 sockets and connects to
        # the v4-mapped address even for an A record, so proxychains' fake-DNS
        # answer (224.0.0.1, see proxy_dns above) reached the kernel as
        # ::ffff:224.0.0.1 — a multicast target, i.e. ENETUNREACH, which the Hub
        # surfaced as "[1500] Internal Client Error: Network is unreachable
        # (license.unity3d.com:443)" and licenses never activated. The hook only
        # rewrites AF_INET connects, so .NET is pinned to IPv4 sockets here and
        # the fake address is proxied like any other.
        export DOTNET_SYSTEM_NET_DISABLEIPV6=1
        # The LD_PRELOAD hook covers the Hub's Node/native side (license client,
        # downloads, Editors it spawns), but Chromium's network stack does not
        # go through libc connect(), so the in-app auth window ignored it and
        # died with ERR_CONNECTION_REFUSED (proved by ss: only the browser
        # process, the CLI and Unity.Licensing had sockets on 10808). Chromium
        # needs its own proxy: --proxy-server routes the Electron network
        # service, and SOCKS5 hostnames are resolved on the proxy side.
        exec "''${HOME}/opt/unityhub/run-hub.sh" --proxy-server="${proxyUrl}" "$@"
      '')

      (pkgs.writeShellScriptBin "unity-proxy" ''
        # The CLI is a Node single-file binary: Node ignores the *_proxy
        # variables on its own, so the CLI's own switch carries the endpoint
        # (--proxy / UNITY_PROXY, `unity --help`); the LD_PRELOAD hook covers
        # every code path that goes through libc instead.
        export UNITY_PROXY=${proxyUrl}
        export http_proxy=${proxyUrl} https_proxy=${proxyUrl} all_proxy=${proxyUrl}
        export HTTP_PROXY=${proxyUrl} HTTPS_PROXY=${proxyUrl} ALL_PROXY=${proxyUrl}
        export no_proxy=localhost,127.0.0.1 NO_PROXY=localhost,127.0.0.1
        export PROXYCHAINS_CONF_FILE=${proxychainsConf}
        export PROXYCHAINS_QUIET_MODE=1
        export LD_PRELOAD=${preloadLib}''${LD_PRELOAD:+:$LD_PRELOAD}
        exec "''${HOME}/.local/bin/unity" "$@"
      '')

      (pkgs.makeDesktopItem {
        name = "unityhub-proxy";
        desktopName = "Unity Hub (via proxy)";
        comment = "Unity Hub launched through the local SOCKS5 proxy";
        exec = "unityhub-proxy %U";
        icon = "unityhub";
        categories = [ "Development" ];
        # hyprctl clients reports the Hub window as class "unityhub" (exactly, no
        # capital letters); the entry has to repeat that or the launcher icon and
        # the window are not associated.
        startupWMClass = "unityhub";
        mimeTypes = [ "x-scheme-handler/unityhub" ];
      })
    ];
  };
}
