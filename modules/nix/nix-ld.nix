{pkgs, ...}: {
  programs.nix-ld = {
    enable = true;
    libraries = [
      pkgs.stdenv.cc.cc # glibc and libstdc++ runtime for foreign binaries

      # Core System
      pkgs.zlib # compression library (zlib1g)
      pkgs.fuse3 # userspace filesystems support
      pkgs.icu # Unicode and locale support
      pkgs.zstd # Zstandard compression
      pkgs.nss # network security services (Mozilla)
      pkgs.openssl # TLS/SSL cryptography library
      pkgs.curl # URL transfer library
      pkgs.libxml2 # XML parsing library
      pkgs.libxslt # XSLT transformation library
      pkgs.libusb1 # USB device access library

      # Graphics
      pkgs.libGL # OpenGL runtime
      pkgs.libva # Video Acceleration API
      pkgs.vulkan-loader # Vulkan ICD loader
      pkgs.mesa # OpenGL/Vulkan drivers
      pkgs.libglvnd # GL vendor-neutral dispatch
      pkgs.libdrm # Direct Rendering Manager

      # X11
      pkgs.xorg.libX11 # core X11 library
      pkgs.xorg.libXext # X11 extensions
      pkgs.xorg.libXi # X11 input extension
      pkgs.xorg.libXrender # X Render extension
      pkgs.xorg.libXtst # X11 test extension
      pkgs.xorg.libXcomposite # X11 compositing
      pkgs.xorg.libXdamage # X11 damage tracking
      pkgs.xorg.libXrandr # X11 resize/rotate
      pkgs.xorg.libXfixes # X11 fixes extension
      pkgs.xorg.libxcb # X11 C bindings
      pkgs.xorg.libXinerama # X11 multi-monitor
      pkgs.xorg.libXcursor # X11 cursor library
      pkgs.xorg.libXScrnSaver # X11 screen saver
      pkgs.xorg.libSM # X11 session management
      pkgs.xorg.libICE # X11 inter-client exchange

      # Wayland
      pkgs.wayland # Wayland protocol library

      # Audio
      pkgs.pipewire # modern audio/video server
      pkgs.alsa-lib # ALSA audio library
      pkgs.pulseaudio # PulseAudio client library

      # Common Libraries
      pkgs.glib # GLib core library
      pkgs.gtk3 # GTK3 toolkit
      pkgs.gtk4 # GTK4 toolkit
      pkgs.libxkbcommon # keyboard handling
      pkgs.freetype # font rendering
      pkgs.fontconfig # font configuration
      pkgs.libpng # PNG image library
      pkgs.libvorbis # Vorbis audio codec
      pkgs.libkrb5 # Kerberos authentication
      pkgs.keyutils # kernel key management
      pkgs.libpsl # public suffix list
      pkgs.nghttp2 # HTTP/2 library
      pkgs.libidn2 # internationalized domain names
    ];
  };
}
