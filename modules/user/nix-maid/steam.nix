{pkgs, ...}: {
  home.packages = [
    (pkgs.writeScriptBin "game-session" (builtins.readFile ./scripts/game-session.sh))
    (pkgs.writeScriptBin "game-session-mangohud" (builtins.readFile ./scripts/game-session-mangohud.sh))
    pkgs.bottles # Wine prefix manager for gaming
    pkgs.dualsensectl # DualSense controller configuration
  ];
}
