{pkgs, ...}: {
  home.packages = [
    (pkgs.writeScriptBin "game-session" (builtins.readFile ./game-session.sh))
    (pkgs.writeScriptBin "game-session-mangohud" (builtins.readFile ./game-session-mangohud.sh))
    pkgs.bottles # Wine prefix manager for gaming
    pkgs.dualsensectl # DualSense controller configuration
  ];
}
