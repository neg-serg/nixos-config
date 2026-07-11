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
    inputs.steam-config-nix.nixosModules.default
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
          # Portal file dialog (xdg-desktop-portal) requires access to the
          # document portal socket to avoid hangs in file-chooser dialogs
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
    ];

    # Expose udev rules/devices used by various game controllers
    hardware.steam-hardware.enable = true;
  };
}
