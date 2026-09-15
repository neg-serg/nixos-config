{
  pkgs,
  lib,
  config,
  neg,
  inputs ? null,
  ...
}:
let
  guiEnabled = config.lib.neg.enabled "gui";

  environment = import ./environment.nix { inherit lib pkgs; };
  services = import ./services.nix { inherit lib pkgs inputs; };
  files = import ./files.nix { inherit lib neg config; };

  # hy3 and hyprspace were removed for the nixos-unstable (Hyprland 0.56)
  # migration (their 0.55 CCompositor/monitor API no longer compiles).
  # hyprland.lua no longer contains @HY3@/@HYPRSPACE@ placeholders, so no
  # store-path injection is needed.
  hyprlandLuaText = builtins.readFile (config.lib.neg.path "files/gui/hypr/hyprland.lua");
in
{
  # System-level Hyprland pieces (hyprglass overlay) — consolidated here from
  # the old `modules/nix` Hyprland module so the whole compositor stack lives in
  # one domain.
  imports = [ ./overlay.nix ];

  config = lib.mkIf guiEnabled (
    lib.mkMerge [
      {
        environment.systemPackages = services.packages;

        systemd.user.targets = services.systemdTargets;
        systemd.user.services = services.systemdServices;
      }

      (files.generateFileLinks {
        hyprlandConfText = environment.hyprlandConf;
        inherit hyprlandLuaText;
      })
    ]
  );
}
