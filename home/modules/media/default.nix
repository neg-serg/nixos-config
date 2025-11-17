{...}: {
  imports = [
    ./apps.nix
    ./audio
    ./ai-upscale.nix
    ./ai-upscale-rt.nix
    ./images
    ./mpv
    ./pipewire.nix
    ./playerctld.nix
  ];
  # moved to playerctld.nix and pipewire.nix
}
