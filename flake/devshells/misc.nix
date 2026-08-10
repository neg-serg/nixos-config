{
  pkgs,
  ...
}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.xephem # astronomy application
    pkgs.xlife # cellular automata explorer
    pkgs.free42 # HP-42S calculator clone
    pkgs.cool-retro-term # retro CRT terminal emulator
    pkgs.almonds # TUI fractal viewer
  ];
}
