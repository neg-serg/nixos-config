{pkgs, ...}: {
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc # glibc and libstdc++ runtime for foreign binaries
      libsForPrograms.nix-ld # general purpose libraries
      libGL # OpenGL
      vulkan-loader # Vulkan ICD loader
      # 32-bit compatibility libraries
      # NOTE: These are often implicitly pulled by libsForPrograms.nix-ld,
      # but explicitly listing them here ensures they are available
      # if some games try to load them directly.
      # You might need to add more 32-bit libraries based on specific game needs.
      libxkbcommon.dev # Common XKB library
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXScrnSaver
      xorg.libXi
      xorg.libXcursor
      xorg.libSM
      xorg.libICE
      alsa-lib
      # For sound
      pulseaudio # Or pipewire if you use it
      # Add more common ones as needed
    ];
  };
}
