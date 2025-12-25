{pkgs, ...}: {
  programs.nix-ld = {
    enable = true;
    libraries = [
      pkgs.stdenv.cc.cc # glibc and libstdc++ runtime for foreign binaries

      # Core System
      pkgs.zlib
      pkgs.fuse3
      pkgs.icu
      pkgs.zstd
      pkgs.nss
      pkgs.openssl
      pkgs.curl
      pkgs.libxml2
      pkgs.libxslt
      pkgs.libusb1

      # Graphics
      pkgs.libGL
      pkgs.libva
      pkgs.vulkan-loader
      pkgs.mesa
      pkgs.libglvnd
      pkgs.libdrm

      # X11
      pkgs.xorg.libX11
      pkgs.xorg.libXext
      pkgs.xorg.libXi
      pkgs.xorg.libXrender
      pkgs.xorg.libXtst
      pkgs.xorg.libXcomposite
      pkgs.xorg.libXdamage
      pkgs.xorg.libXrandr
      pkgs.xorg.libXfixes
      pkgs.xorg.libxcb
      pkgs.xorg.libXinerama
      pkgs.xorg.libXcursor
      pkgs.xorg.libXScrnSaver
      pkgs.xorg.libSM
      pkgs.xorg.libICE

      # Wayland
      pkgs.wayland

      # Audio
      pkgs.pipewire
      pkgs.alsa-lib
      pkgs.pulseaudio

      # Common Libraries
      pkgs.glib
      pkgs.gtk3
      pkgs.gtk4
      pkgs.libxkbcommon
      pkgs.freetype
      pkgs.fontconfig
      pkgs.libpng
      pkgs.libvorbis
      pkgs.libkrb5
      pkgs.keyutils
      pkgs.libpsl
      pkgs.nghttp2
      pkgs.libidn2
    ];
  };
}
