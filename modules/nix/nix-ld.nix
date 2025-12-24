{pkgs, ...}: {
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc # glibc and libstdc++ runtime for foreign binaries

      # Core System
      zlib
      fuse3
      icu
      zstd
      nss
      openssl
      curl
      libxml2
      libxslt
      libusb1

      # Graphics
      libGL
      libva
      vulkan-loader
      mesa
      libglvnd
      libdrm

      # X11
      xorg.libX11
      xorg.libXext
      xorg.libXi
      xorg.libXrender
      xorg.libXtst
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXrandr
      xorg.libXfixes
      xorg.libxcb
      xorg.libXinerama
      xorg.libXcursor
      xorg.libXScrnSaver
      xorg.libSM
      xorg.libICE

      # Wayland
      wayland

      # Audio
      pipewire
      alsa-lib
      pulseaudio

      # Common Libraries
      glib
      gtk3
      gtk4
      libxkbcommon
      freetype
      fontconfig
      libpng
      libvorbis
      libkrb5
      keyutils
      libpsl
      nghttp2
      libidn2
    ];
  };
}
