# Game Launchers Module
#
# Steam, Heroic, Prismlauncher and other game launchers.
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.profiles.games or {};
in {
  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      package = pkgs.steam.override {
        extraBwrapArgs = ["--bind" "/zero" "/zero"];
        extraPkgs = pkgs': let
          mkDeps = pkgsSet:
            with pkgsSet; [
              # Core X11 libs required by many titles
              xorg.libX11
              xorg.libXext
              xorg.libXrender
              xorg.libXi
              xorg.libXinerama
              xorg.libXcursor
              xorg.libXScrnSaver
              xorg.libSM
              xorg.libICE
              xorg.libxcb
              xorg.libXrandr

              # Common multimedia/system libs
              libxkbcommon
              freetype
              fontconfig
              glib
              libpng
              libpulseaudio
              libvorbis
              libkrb5
              keyutils
              openal
              zlib

              # GL/Vulkan plumbing for AMD on X11 (host RADV)
              libglvnd
              libdrm
              vulkan-loader
              libGLU

              # libstdc++ for the runtime
              (lib.getLib stdenv.cc.cc)

              # Network/Auth libs often needed by Steam Runtime tools
              openssl
              libpsl
              nghttp2
              libidn2
            ];
        in
          mkDeps pkgs';
      };
      dedicatedServer.openFirewall = true;
      gamescopeSession.enable = true;
      remotePlay.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      extraCompatPackages = [pkgs.proton-ge-bin];
    };

    environment.systemPackages = [
      pkgs.protontricks # winetricks-like helper tailored for Steam Proton
      pkgs.prismlauncher # Minecraft launcher
      pkgs.heroic # Epic, GOG, Amazon launcher
    ];

    # Expose udev rules/devices used by various game controllers
    hardware.steam-hardware.enable = true;
  };
}
