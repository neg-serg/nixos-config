{ pkgs, ... }:
{
  environment.systemPackages = [
    (pkgs.writeScriptBin "game-session" (builtins.readFile ../scripts/game-session.sh)) # Desktop session launcher for gaming
    (pkgs.writeScriptBin "game-session-mangohud" (
      builtins.readFile ../scripts/game-session-mangohud.sh
    )) # Game session launcher with MangoHud
    pkgs.bottles # Wine prefix manager for gaming
    pkgs.dualsensectl # DualSense controller configuration
  ];
}
