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

  # Same on-demand root the fun module uses; both modules only contribute the
  # PATH wrapper, so the launcher derivation is identical and deduplicated.
  onDemand = config.lib.neg.onDemand pkgs;

  # GE-Proton is a 1.5 GiB unpacked tree (the tarball itself, re-exported as a
  # compatibility tool) and Steam only reads it when a game asks for that
  # tool. Instead of `programs.steam.extraCompatPackages` — which links it
  # into the Steam runtime and therefore into the system closure — a login
  # oneshot builds it into a GC root and links that root into the user's
  # compatibilitytools.d. The tool's own compatibilitytool.vdf expects exactly
  # that layout: a subdirectory whose install_path is ".".
  protonGeEnsure = pkgs.writeShellScriptBin "steam-proton-ge-ensure" ''
    set -eu
    nix=${config.nix.package}/bin/nix
    nixStore=${config.nix.package}/bin/nix-store
    root="$HOME/.local/state/nix-apps/proton-ge-bin"

    if [ ! -e "$root" ]; then
      mkdir -p "$(dirname "$root")"
      rm -f "$root"
      # `^*` is required: the manifest-bearing `steamcompattool` output is not
      # the default one, and a plain `--print-out-paths` would only return the
      # unpacked `out`. Both lines are printed, so the candidate is filtered.
      out=$("$nix" build --no-link --print-out-paths "git+file:///etc/nixos#proton-ge-bin^*" |
        # Two outputs: `out` is the unpacked build, `steamcompattool` is the
        # manifest-bearing wrapper Steam expects. `--print-out-paths` prints
        # both, and `--add-root` rejects the newline-joined pair.
        while IFS= read -r candidate; do
          case "$candidate" in
            *-steamcompattool) printf '%s\n' "$candidate"; break ;;
          esac
        done)
      "$nixStore" --add-root "$root" --indirect --realise "$out" >/dev/null
    fi

    target=$(readlink -f "$root")
    # Store basenames carry a 32-char hash prefix: <hash>-proton-ge-bin-GE-Proton11-11-steamcompattool
    name=$(basename "$target" | sed -e 's/^[a-z0-9]\{32\}-//' -e 's/^proton-ge-bin-//' -e 's/-steamcompattool$//')
    compat="$HOME/.local/share/Steam/compatibilitytools.d"
    mkdir -p "$compat"

    # Drop links to older store paths of ours. protonup-ng installs real
    # directories in the same place, so only symlinks into the store are
    # touched and only when they are not the current target.
    for stale in "$compat"/GE-Proton*; do
      [ -L "$stale" ] || continue
      resolved=$(readlink -f "$stale")
      case "$resolved" in
        /nix/store/*) [ "$resolved" = "$target" ] || rm -f "$stale" ;;
      esac
    done

    ln -sfn "$target" "$compat/$name"
  '';
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
        #
        # Steam's own game launch chain starts steamrt64/reaper, a 32-bit
        # i386 binary whose interpreter is /lib/ld-linux.so.2, and Steam
        # preloads its 32-bit gameoverlayrenderer.so into it, so the sandbox
        # needs i686 glibc plus libGL (the reaper never resolves a vendor
        # driver). Without them every launch dies in under a second before
        # Proton starts, so multiArch must stay on. What we drop is the rest
        # of steam's i686 multiPkgs (mesa/llvm, NetworkManager, glibc-locales,
        # ~1.1 GiB NAR / ~0.5 GiB on ZFS): the 32-bit side gets only glibc and
        # libglvnd. 32-bit games therefore need graphics from outside the
        # closure: `just rct32-mesa` builds pkgsi686Linux.mesa into the user GC
        # root ~/.local/state/rct32-mesa, and the game's Steam launch options
        # point LD_LIBRARY_PATH/LIBGL_DRIVERS_PATH at it (llvmpipe plus
        # PROTON_USE_WINED3D, so no 32-bit Vulkan driver is needed). The system
        # closure stays free of the 32-bit graphics stack; RCT Classic
        # (app 683900) runs this way.
        buildFHSEnv =
          args:
          pkgs.buildFHSEnv (
            args
            // {
              multiArch = true;
              multiPkgs =
                p:
                if p.stdenv.hostPlatform.is32bit then
                  [
                    p.glibc
                    p.libGL
                  ]
                else
                  args.multiPkgs p;
            }
          );
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
        ++ lib.optionals (config.lib.neg.enabled "games.steamProxy") [
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
      # GE-Proton (community Proton build with more patches) is materialised
      # into ~/.local/share/Steam/compatibilitytools.d by protonGeEnsure below
      # rather than through extraCompatPackages, which would put the unpacked
      # 1.5 GiB build into the system closure.
    };

    # Steam cannot route its native CM connections (WebSocket 27018-27036)
    # through SOCKS5 via env vars — it ignores ALL_PROXY. When
    # features.games.steamProxy is enabled, the launcher above is wrapped with
    # proxychains LD_PRELOAD so all outbound TCP goes through the local SOCKS5
    # proxy. Env proxies are stripped inside to avoid double-routing.
    environment.etc."proxychains/proxychains.conf" =
      lib.mkIf (config.lib.neg.enabled "games.steamProxy")
        {
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
      (onDemand {
        name = "protontricks";
        attr = "protontricks";
        aliases = [ "protontricks-launch" ];
      }) # winetricks-like helper tailored for Steam Proton, built on first use
      protonGeEnsure # re-link GE-Proton into Steam's compatibilitytools.d
    ];

    systemd.user.services.steam-proton-ge = config.lib.neg.systemdUser.mkUserOneshot {
      description = "Steam — link GE-Proton into compatibilitytools.d";
      script = "${protonGeEnsure}/bin/steam-proton-ge-ensure";
      after = [ "network.target" ];
    };

    # Expose udev rules/devices used by various game controllers
    hardware.steam-hardware.enable = true;
  };
}
