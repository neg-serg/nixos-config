# Game Launchers Module
#
# Steam, Heroic, Prismlauncher and other game launchers.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.profiles.games or { };
in
{
  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      package = pkgs.steam.override {
        # Digital distribution platform
        extraBwrapArgs = [
          "--bind"
          "/zero"
          "/zero"
        ];
        extraPkgs =
          pkgs':
          let
            mkDeps =
              pkgsSet: with pkgsSet; [
                # Core X11 libs required by many titles
                xorg.libX11 # X11 protocol client library
                xorg.libXext # X11 extension library
                xorg.libXrender # X11 Render extension library
                xorg.libXi # X11 Input extension library
                xorg.libXinerama # X11 Xinerama extension library
                xorg.libXcursor # X11 Cursor management library
                xorg.libXScrnSaver # X11 Screen Saver extension library
                xorg.libSM # X11 Session Management library
                xorg.libICE # X11 Inter-Client Exchange library
                xorg.libxcb # X11 C Binding library
                xorg.libXrandr # X11 Resize, Rotate and Reflection extension library

                # Common multimedia/system libs
                libxkbcommon # keyboard layout management
                freetype # font rendering engine
                fontconfig # font configuration library
                glib # core application building block
                libpng # PNG image format library
                libpulseaudio # PulseAudio client library
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

    environment.systemPackages = [
      pkgs.protontricks # winetricks-like helper tailored for Steam Proton
    ]
    ++ (lib.optionals (config.features.games.launchers.prismlauncher.enable or true) [
      pkgs.prismlauncher # Minecraft launcher
    ])
    ++ (lib.optionals (config.features.games.launchers.heroic.enable or true) [
      pkgs.heroic # Epic, GOG, Amazon launcher
    ]);

    # Expose udev rules/devices used by various game controllers
    hardware.steam-hardware.enable = true;
  };
}
