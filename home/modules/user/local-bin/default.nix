{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
  mkIf (config.features.gui.enable or false) (lib.mkMerge [
    {
      # Runtime dependencies for local-bin scripts
      home.packages = config.lib.neg.pkgsList [
        # core tools
        pkgs.fd # fast file finder used by pl/read_documents
        pkgs.jq # JSON processor for various helpers
        pkgs.curl # HTTP client for pb/swd
        pkgs.git # used by nb (notes repo updates)
        pkgs.imagemagick # convert/mogrify for screenshot/swayimg-actions
        pkgs.libnotify # notify-send for pic-notify/qr/screenshot
        pkgs.socat # UNIX sockets (swayimg/Hyprland IPC)
        # fasd removed; use zoxide for ranking
        pkgs.usbutils # lsusb (unlock Yubikey detection)
        # audio/video + helpers (mpv comes from media stack)
        # playerctl/mpc now come from the global system package list.
        pkgs.wireplumber # wpctl for vol/pl volume control
        # wayland utils now provided system-wide
        # archive helpers shared across scripts (clip/punzip/etc.)
        pkgs.unar # extract .rar archives
        pkgs.p7zip # 7z extraction
        pkgs.lbzip2 # fast bzip2 backend for tar
        pkgs.rapidgzip # parallel gzip backend for tar/raw gz
        pkgs.xz # xz backend for tar/unxz
        pkgs.unzip # unzip (used via punzip helper)
        # image/qr/info
        pkgs.qrencode # generate QR codes (qr gen)
        pkgs.zbar # scan QR from image (qr)
        pkgs.exiftool # EXIF metadata (pic-notify)
        # audio features extractor for music-index/music-similar
        pkgs.essentia-extractor # streaming_extractor_music binary
        pkgs.neg.music_clap # CLAP embeddings CLI (PyTorch + laion_clap)
        # pkgs.neg.blissify_rs # playlist generation via audio descriptors (temporarily disabled)
        # shell utils for menus and translations
        pkgs.translate-shell # trans CLI (main-menu translate)
        # ALSA fallback for volume control
        pkgs.alsa-utils # amixer (vol fallback)
        # audio tools
        pkgs.sox # spectrograms (flacspec)
        # Note: Xvfb (xorg.xvfb) conflicts with newer xwayland in the
        # Home Manager buildEnv (both ship lib/xorg/protocol.txt).
        # Do not include by default to avoid closure collisions when
        # Hyprland pulls in xwayland. The exorg script will work if
        # Xvfb is available on PATH (install xorg.xvfb when needed).
        # document viewer for read_documents
        pkgs.zathura # PDF/DJVU/EPUB viewer (rofi file-browser)
        # notify daemon (dunstify) provided by dunst service; ensure package present
        pkgs.dunst # desktop notifications backend
        # inotify for shot-optimizer and pic-dirs-list
        pkgs.inotify-tools # inotifywait monitor for folders
        # downloaders for clip (YouTube DL + aria2 backend)
        pkgs.yt-dlp # video downloader
        pkgs.aria2 # segmented downloader (yt-dlp --downloader)
        pkgs.neg.bpf_host_latency # trace DNS lookup latency via BCC/eBPF (root)
        pkgs.neg.albumdetails # album metadata extractor for music-rename
      ];
    }
    # Generate ~/.local/bin scripts using mkLocalBin (pre-clean + exec + force)
    {
      home.file = let
        mkEnt = e: {
          name = ".local/bin/${e.name}";
          value = {
            executable = true;
            force = true;
            text = builtins.readFile e.src;
          };
        };
        scripts = [
          {
            name = "color";
            src = ./scripts/color;
          }
          {
            name = "browser_profile_migrate.py";
            src = ./scripts/browser_profile_migrate.py;
          }
          {
            name = "main-menu";
            src = ./scripts/main-menu.sh;
          }
          {
            name = "hypr-shortcuts";
            src = ./scripts/hypr-shortcuts.sh;
          }
          {
            name = "mpd-add";
            src = ./scripts/mpd-add.sh;
          }
          {
            name = "swayimg-actions.sh";
            src = ./scripts/swayimg-actions.sh;
          }
          {
            name = "clip";
            src = ./scripts/clip.sh;
          }
          {
            name = "pl";
            src = ./scripts/pl.sh;
          }
          {
            name = "wl";
            src = ./scripts/wl.sh;
          }
          {
            name = "music-rename";
            src = ./scripts/music-rename.sh;
          }
          {
            name = "unlock";
            src = ./scripts/unlock.sh;
          }
          {
            name = "pic-notify";
            src = ./scripts/pic-notify.sh;
          }
          {
            name = "pic-dirs-list";
            src = ./scripts/pic-dirs-list.sh;
          }
          {
            name = "any";
            src = ./scripts/any;
          }
          {
            name = "beet-update";
            src = ./scripts/beet-update;
          }
          # Legacy image wrapper removed (sxivnc); use swayimg-first directly
          {
            name = "flacspec";
            src = ./scripts/flacspec;
          }
          {
            name = "iommu-info";
            src = ./scripts/iommu-info;
          }
          {
            name = "nb";
            src = ./scripts/nb;
          }
          {
            name = "neovim-autocd.py";
            src = ./scripts/neovim-autocd.py;
          }
          {
            name = "nix-updates";
            src = ./scripts/nix-updates;
          }
          {
            name = "pb";
            src = ./scripts/pb;
          }
          {
            name = "pngoptim";
            src = ./scripts/pngoptim;
          }
          {
            name = "pass-2col";
            src = ./scripts/pass-2col;
          }
          {
            name = "qr";
            src = ./scripts/qr;
          }
          {
            name = "read_documents";
            src = ./scripts/read_documents;
          }
          {
            name = "ren";
            src = ./scripts/ren;
          }
          {
            name = "screenshot";
            src = ./scripts/screenshot;
          }
          {
            name = "shot-optimizer";
            src = ./scripts/shot-optimizer;
          }
          {
            name = "swd";
            src = ./scripts/swd;
          }
          {
            name = "vol";
            src = ./scripts/vol;
          }
          {
            name = "mp";
            src = ./scripts/mp;
          }
          {
            name = "mpd_del_album";
            src = ./scripts/mpd_del_album;
          }
          {
            name = "music-index";
            src = ./scripts/music-index;
          }
          {
            name = "music-similar";
            src = ./scripts/music-similar;
          }
          {
            name = "music-highlevel";
            src = ./scripts/music-highlevel;
          }
          {
            name = "cidr";
            src = ./scripts/cidr;
          }
          {
            name = "punzip";
            src = ./scripts/punzip;
          }

          {
            name = "v";
            src = ./scripts/v.sh;
          }
          {
            name = "journal-clean";
            src = ./scripts/journal-clean.sh;
          }
        ];
        base = builtins.listToAttrs (map mkEnt scripts);
        # Special case: vid-info needs path substitution for libs
        sp = pkgs.python3.sitePackages;
        libpp = "${pkgs.neg.pretty_printer}/${sp}";
        libcolored = "${pkgs.python3Packages.colored}/${sp}";
        tpl = builtins.readFile ./scripts/vid-info.py;
        vidInfoText = lib.replaceStrings ["@LIBPP@" "@LIBCOLORED@"] [libpp libcolored] tpl;
        # Special case: ren needs path substitution for libs as well
        renTpl = builtins.readFile ./scripts/ren;
        renText = lib.replaceStrings ["@LIBPP@" "@LIBCOLORED@"] [libpp libcolored] renTpl;
        picInfoText = builtins.readFile ./scripts/pic-info;
      in
        base
        // {
          ".local/bin/vid-info" = {
            executable = true;
            force = true;
            text = vidInfoText;
          };
          ".local/bin/ren" = {
            executable = true;
            force = true;
            text = renText;
          };
          ".local/bin/pic-info" = {
            executable = true;
            force = true;
            text = picInfoText;
          };
          # Provide a stable wrapper for Pyprland CLI with absolute path,
          # so Hypr bindings don't rely on PATH. Kept at ~/.local/bin/pypr-client
          # to preserve existing config and muscle memory.
          ".local/bin/pypr-client" = {
            executable = true;
            force = true;
            text = let
              exe = lib.getExe' pkgs.pyprland "pypr";
            in ''
              #!/usr/bin/env bash
              set -euo pipefail
              exec ${exe} "$@"
            '';
          };
          # Robust starter for Pyprland: determines the current Hyprland
          # instance signature before launching so that restarts/crashes
          # of Hyprland don't leave pyprland bound to a stale socket.
          ".local/bin/pypr-run" = {
            executable = true;
            force = true;
            text = let
              exe = lib.getExe' pkgs.pyprland "pypr";
            in ''
              #!/usr/bin/env bash
              set -euo pipefail

              runtime="$XDG_RUNTIME_DIR"
              if [ -z "$runtime" ]; then
                runtime="/run/user/$(id -u)"
              fi
              sig="$HYPRLAND_INSTANCE_SIGNATURE"

              # Validate existing signature; otherwise select newest hypr instance
              if [ -n "$sig" ] && [ -S "$runtime/hypr/$sig/.socket.sock" ]; then
                :
              else
                if [ -d "$runtime/hypr" ]; then
                  newest="$(ls -td "$runtime/hypr"/* 2>/dev/null | head -n1 || true)"
                  if [ -n "$newest" ]; then
                    cand="$(basename -- "$newest" || true)"
                    if [ -S "$runtime/hypr/$cand/.socket.sock" ] || [ -S "$runtime/hypr/$cand/.socket2.sock" ]; then
                      sig="$cand"
                    else
                      sig=""
                    fi
                  fi
                else
                  sig=""
                fi
              fi

              if [ -z "$sig" ]; then
                echo "pypr-run: Hyprland not detected (no signature)." >&2
                exit 1
              fi

              export HYPRLAND_INSTANCE_SIGNATURE="$sig"
              exec ${exe} "$@"
            '';
          };
        };
    }
    # Cleanup: ensure any old ~/.local/bin/raise (from previous config) is removed
    # No per-activation cleanup: keep activation quiet. If legacy ~/.local/bin/raise
    # exists, it can be removed manually.
  ])
